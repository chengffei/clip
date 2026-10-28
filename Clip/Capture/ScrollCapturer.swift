import AppKit
import Vision

final class ScrollCapturer {
    private struct ImageFormat {
        let bitsPerComponent: Int
        let bitsPerPixel: Int
        let bitmapInfo: CGBitmapInfo
        let colorSpace: CGColorSpace
    }

    private struct CapturedFrame {
        let image: NSImage
        let bitmap: BitmapData
    }

    /// Result of a single capture attempt, used by auto-scroll to decide
    /// whether the page kept producing fresh content or has bottomed out.
    enum FrameOutcome {
        /// A new frame with fresh content was stitched in.
        case appended
        /// The frame was a duplicate, too similar, or failed — no progress.
        case noNewContent
        /// The frame budget is exhausted; capturing should stop.
        case atFrameLimit
        /// The frame shares no rows with the last accepted one.
        case noOverlap
    }

    var onPreviewUpdated: ((NSImage) -> Void)?
    /// Readable from any thread without waiting on the capture queue, which
    /// may itself be waiting on the main thread.
    var frameCount: Int { countLock.withLock { storedFrameCount } }
    private let countLock = NSLock()
    private var storedFrameCount = 0

    private let captureRect: CGRect
    private let screen: NSScreen
    /// capcap's own scroll-capture chrome (e.g. the hint toast) — excluded
    /// from every captured frame so it never appears in the stitched image.
    private let excludedWindowNumbers: [CGWindowID]
    private let captureQueue = DispatchQueue(label: "capcap.scroll-capture", qos: .userInitiated)
    private let maxFrames = 100
    private let initialCaptureTimeout: TimeInterval = 3.0
    private let settledCaptureTimeout: TimeInterval = 1.5

    private var frames: [CapturedFrame] = [] {
        didSet { countLock.withLock { storedFrameCount = frames.count } }
    }
    private var overlaps: [Int] = []
    /// Live frames while the user scrolls; nil when replaying in tests.
    private var stream: ScrollFrameStream?
    /// The newest frame that overlapped the last accepted one but added too
    /// little to keep. If the next frame no longer overlaps the last accepted
    /// one, this bridges the gap.
    private var pendingFrame: (frame: CapturedFrame, overlap: Int, up: Bool)?
    /// Set by the first accepted step. Terminals keep the newest output at the
    /// bottom, so people often scroll up; frames are then stored in capture
    /// order and stitched bottom-up (2026-10-28).
    private var scrollsUp: Bool?
    /// Mean pixel difference of the overlap `findOverlap` last settled on;
    /// lower is a closer match. Infinity when it found none.
    private var lastMatchScore: Double = .infinity

    // MARK: - Sticky element exclusion state
    //
    // Pages with persistent UI (scrollbars on the right, sticky nav bars
    // at the top) confuse Vision's translational image registration: the
    // scrollbar slider sits in a different place between frames at a
    // different rate than page content, and a sticky header doesn't move
    // at all. Vision treats both regions as evidence and reports a
    // translation that splits the difference — typically much smaller
    // than the page's actual scroll offset. We detect both regions once
    // per session from the first usable frame pair and crop them out of
    // every image fed into Vision afterwards.
    private var scrollbarWidthPx: Int = 0
    private var scrollbarDetected: Bool = false
    private var stickyHeaderPx: Int = 0
    /// Rows at the bottom that stay put while the content scrolls (an app's
    /// tab bar or Save button). The smallest band seen across accepted pairs,
    /// so blank content that happened to match once is not mistaken for it.
    private var stickyFooterPx: Int?
    private var previewFooterTrimmed = false
    private var stickyHeaderDetectionDone: Bool = false
    private var stickyHeaderSamplesTaken: Int = 0

    // Incremental preview state
    private var previewBitmap: BitmapData?
    private var previewHeightPixels: Int = 0
    private var previewScale: CGFloat = 1
    private var previewPointWidth: CGFloat = 0

    init(
        rect: CGRect,
        screen: NSScreen,
        excludingWindowNumbers: [CGWindowID] = []
    ) {
        // Fractional point rects made ScreenCaptureKit resample every frame,
        // which visibly softened long screenshots next to ordinary ones
        // (2026-10-27). Snap outward to whole device pixels so frames are
        // copied 1:1.
        let rect = Self.pixelAligned(rect, scale: screen.backingScaleFactor)
        self.captureRect = rect
        self.screen = screen
        FileLog.write(String(format: "scroll capture rect %.2f,%.2f %.2fx%.2f scale=%.0f", rect.minX, rect.minY, rect.width, rect.height, screen.backingScaleFactor))
        self.excludedWindowNumbers = excludingWindowNumbers

        // Open with the stream's own first frame, so the user can't scroll
        // away before tracking starts; fall back to a one-shot capture.
        let stream = ScrollFrameStream(rect: rect, screen: screen, excludingWindowNumbers: excludingWindowNumbers)
        self.stream = stream
        let started = Date()
        let opening = stream.waitForFirstFrame(timeout: 1.5) ?? ScreenCapturer.capture(
            rect: rect,
            screen: screen,
            excludingWindowNumbers: excludingWindowNumbers,
            timeout: initialCaptureTimeout
        )
        FileLog.write(String(format: "scroll capture opening frame %@ after %.0fms", stream.isRunning ? "from stream" : "one-shot", Date().timeIntervalSince(started) * 1000))
        if let image = opening, let bitmap = bitmapData(from: image) {
            let firstFrame = CapturedFrame(image: image, bitmap: bitmap)
            frames.append(firstFrame)
            initPreview(from: firstFrame)
            trackedFrame = firstFrame
        }
        // Property observers do not run inside init, so seed the count here.
        storedFrameCount = frames.count
    }

    /// Test hook: runs the accept and stitch logic over prepared frames
    /// without touching the screen.
    static func stitchForTesting(_ images: [NSImage]) -> (accepted: Int, image: NSImage?) {
        let capturer = ScrollCapturer(replaying: images)
        return capturer.captureQueue.sync {
            let image = capturer.frames.count > 1 ? capturer.stitchAcceptedFrames() : capturer.frames.first?.image
            return (capturer.frames.count, image)
        }
    }

    deinit { stream?.stop() }

    private init(replaying images: [NSImage]) {
        captureRect = .zero
        screen = NSScreen.main ?? NSScreen.screens[0]
        excludedWindowNumbers = []
        for image in images { _ = consider(image) }
    }

    static func pixelAligned(_ rect: CGRect, scale: CGFloat) -> CGRect {
        let scale = max(scale, 1)
        let minX = (rect.minX * scale).rounded(.down) / scale
        let minY = (rect.minY * scale).rounded(.down) / scale
        let maxX = (rect.maxX * scale).rounded(.up) / scale
        let maxY = (rect.maxY * scale).rounded(.up) / scale
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    func stopAndStitch(completion: @escaping (NSImage?) -> Void) {
        captureQueue.async {
            var result: NSImage?

            if let stream = self.stream, stream.isRunning {
                // Let the last scroll land, then take the final state from the
                // stream too: one-shot captures can differ from stream frames
                // by a few color levels, enough to misplace a seam by a line.
                Thread.sleep(forTimeInterval: 0.15)
                _ = self.considerStreamBatch(stream.takeNewFrames(), finalFrame: true)
                self.keepTrackedFrameIfAhead()
                stream.stop()
                self.stream = nil
            } else {
                self.stream?.stop()
                self.stream = nil
                // One last frame so the final scrolled state is never missed.
                self.captureFrame(expectedShiftPoints: 0)
            }
            FileLog.write("scroll capture polls rejected: noImage=\(self.rejectedNoImage) identical=\(self.rejectedIdentical) smallShift=\(self.rejectedSmallShift) lastOverlap=\(self.lastRejectedOverlap.map { "\($0.overlap)/\($0.height)" } ?? "-")")

            guard !self.frames.isEmpty else {
                result = nil
                DispatchQueue.main.async {
                    completion(result)
                }
                return
            }

            if self.frames.count == 1 {
                result = self.frames[0].image
                DispatchQueue.main.async {
                    completion(result)
                }
                return
            }

            result = self.stitchAcceptedFrames()

            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    /// Captures one frame right away and reports the outcome. Used while the
    /// user scrolls: waiting for the page to settle made polls ~1.5s apart,
    /// and a fast scroll then left no overlap between frames (2026-10-28).
    func captureSynchronously(expectedShiftPoints: CGFloat) -> FrameOutcome {
        var outcome: FrameOutcome = .noNewContent
        captureQueue.sync {
            outcome = captureFrame(expectedShiftPoints: expectedShiftPoints, settled: false)
        }
        return outcome
    }

    /// Captures a frame, polling until two consecutive captures produce
    /// byte-identical raw pixel data (the page has stopped re-rendering)
    /// or a timeout elapses. This guards the Vision-based overlap detector
    /// against measuring an in-progress smooth-scroll animation — without
    /// it, fast synthetic scrolls catch the page mid-render and Vision
    /// reports partial offsets that defeat the stitching loop.
    ///
    /// Returns the settled image, or the most-recent capture if settlement
    /// times out (so the loop still progresses rather than failing hard).
    private func captureSettledFrame() -> NSImage? {
        var previousData: Data? = nil
        var lastImage: NSImage? = nil
        var waitNs: UInt64 = 12_000_000   // start polling at 12ms
        let deadline = Date().addingTimeInterval(settledCaptureTimeout)

        // ~20 iterations × 12–80ms backoff ≈ up to ~1s total wait, which is
        // more than enough for typical smooth-scroll animations (150–300ms).
        for _ in 0..<20 {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { break }
            guard let image = ScreenCapturer.capture(
                rect: captureRect,
                screen: screen,
                excludingWindowNumbers: excludedWindowNumbers,
                timeout: remaining
            ) else {
                sleepUntilDeadline(min(0.03, deadline.timeIntervalSinceNow))
                continue
            }

            // Compare raw pixel bytes from the CGImage's data provider —
            // a deterministic per-pixel signature. Two consecutive identical
            // signatures mean the compositor isn't drawing anything new, so
            // the page is settled. Using raw bytes avoids the encode /
            // compress overhead of tiffRepresentation, which matters on
            // high-DPI displays where the loop runs many times per step.
            guard
                let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
                let signature = cgImage.dataProvider?.data as Data?
            else {
                sleepUntilDeadline(min(Double(waitNs) / 1_000_000_000, deadline.timeIntervalSinceNow))
                continue
            }

            if let prev = previousData, prev == signature {
                return image
            }

            previousData = signature
            lastImage = image
            sleepUntilDeadline(min(Double(waitNs) / 1_000_000_000, deadline.timeIntervalSinceNow))
            // Geometric backoff so we don't busy-poll for long animations.
            waitNs = min(waitNs * 3 / 2, 80_000_000)
        }

        // Timeout — return whatever we have. The caller's dedup check
        // (imagesAreNearlyIdentical) will still catch the no-progress case
        // and report .noNewContent appropriately.
        return lastImage
    }

    private func sleepUntilDeadline(_ interval: TimeInterval) {
        guard interval > 0 else { return }
        Thread.sleep(forTimeInterval: interval)
    }

    /// Why polls were turned away, summarised in the log when capture stops.
    private var rejectedNoImage = 0
    private var rejectedIdentical = 0
    private var rejectedSmallShift = 0
    private var lastRejectedOverlap: (overlap: Int, height: Int)?

    @discardableResult
    private func captureFrame(expectedShiftPoints _: CGFloat, settled: Bool = true) -> FrameOutcome {
        guard frames.count < maxFrames else {
            return .atFrameLimit
        }
        let captured: NSImage?
        if settled {
            captured = captureSettledFrame()
        } else if let stream, stream.isRunning {
            return considerStreamBatch(stream.takeNewFrames())
        } else {
            captured = ScreenCapturer.capture(rect: captureRect, screen: screen,
                                              excludingWindowNumbers: excludedWindowNumbers, timeout: 1)
        }
        guard let image = captured else {
            rejectedNoImage += 1
            return .noNewContent
        }
        if settled, trackedFrame != nil || trackingLost, let bitmap = bitmapData(from: image) {
            return track(CapturedFrame(image: image, bitmap: bitmap), minimumNewRows: 8)
        }
        // Polls run every 80ms; keep only frames that add a real step so the
        // frame budget covers long pages. The final settled frame takes any
        // remainder.
        return consider(image, minimumNewFraction: settled ? 1.0 / 200 : 1.0 / 4)
    }

    // MARK: - Stream tracking
    //
    // Matching each new frame against the last *kept* one meant searching
    // shifts of hundreds of pixels, and on repetitive text (terminals, logs)
    // a shift off by whole blocks of lines matched just as well: lines went
    // missing or repeated (2026-10-28). Stream frames arrive ~16ms apart, so
    // instead follow the motion frame to frame, where shifts are small and
    // predictable, add them up to a position on the page, and keep a frame
    // whenever it reveals a quarter screen of new content.

    private var trackedFrame: CapturedFrame?
    /// Page offset of `trackedFrame` relative to the first frame, in pixels;
    /// positive is further down the page.
    private var trackedPosition = 0
    /// Page offset of `frames.last`.
    private var keptPosition = 0
    private var lastStep = 0
    private var trackingLost = false

    private func considerStreamBatch(_ batch: [NSImage], finalFrame: Bool = false) -> FrameOutcome {
        var outcome: FrameOutcome = .noNewContent
        for (index, image) in batch.enumerated() {
            guard frames.count < maxFrames else { return .atFrameLimit }
            guard let bitmap = bitmapData(from: image) else { continue }
            let frame = CapturedFrame(image: image, bitmap: bitmap)
            // The opening frame was a one-shot capture; swap in the stream's
            // own view of the same screen so every seam compares like with like.
            if frames.count == 1, trackedFrame == nil,
               imagesAreNearlyIdentical(frames[0].bitmap, bitmap) {
                frames[0] = frame
                initPreview(from: frame)
                trackedFrame = frame
                continue
            }
            let last = finalFrame && index == batch.count - 1
            let result = track(frame, minimumNewRows: last ? 8 : max(8, bitmap.height / 4))
            if result == .appended || outcome != .appended { outcome = result }
        }
        return outcome
    }

    private func track(_ frame: CapturedFrame, minimumNewRows: Int) -> FrameOutcome {
        guard frames.count < maxFrames else { return .atFrameLimit }
        guard let kept = frames.last else {
            frames.append(frame)
            initPreview(from: frame)
            trackedFrame = frame
            return .appended
        }
        let reference = trackedFrame ?? kept
        if imagesAreNearlyIdentical(reference.bitmap, frame.bitmap) {
            rejectedIdentical += 1
            return .noNewContent
        }
        if !trackingLost,
           let step = trackShift(previous: reference.bitmap, current: frame.bitmap, predicted: lastStep) {
            trackedPosition += step
            lastStep = step
            if ProcessInfo.processInfo.environment["CLIP_TRACE_TRACKING"] != nil {
                FileLog.write("scroll track step \(step) position \(trackedPosition)")
            }
        } else {
            // Lost the motion (a jump too big for one frame): find the frame
            // against the last kept one instead.
            let step = measureStep(from: kept, to: frame, minimumNewRows: 1)
            guard step.newRows > 0 else {
                trackingLost = true
                rejectedSmallShift += 1
                return .noOverlap
            }
            if trackingLost { FileLog.write("scroll capture tracking regained") }
            trackingLost = false
            trackedPosition = keptPosition + (step.up ? -step.newRows : step.newRows)
            lastStep = 0
        }
        trackedFrame = frame

        let height = frame.bitmap.height
        let advance = trackedPosition - keptPosition
        let up = scrollsUp ?? (advance < 0)
        let newRows = up ? -advance : advance
        guard newRows >= minimumNewRows else {
            rejectedSmallShift += 1
            return .noNewContent
        }
        guard newRows < height else {
            FileLog.write("scroll capture tracking lost: step \(lastStep) left no overlap")
            trackingLost = true
            return .noOverlap
        }
        accept(frame, overlap: height - newRows, up: up)
        keptPosition = trackedPosition
        return .appended
    }

    /// On stop: the newest tracked frame may hold less than a quarter screen
    /// of new content; keep it so the end of the scroll isn't lost.
    private func keepTrackedFrameIfAhead() {
        guard !trackingLost, let frame = trackedFrame, frames.count < maxFrames,
              frame.image !== frames.last?.image else { return }
        let advance = trackedPosition - keptPosition
        let up = scrollsUp ?? (advance < 0)
        let newRows = up ? -advance : advance
        guard newRows >= 8, newRows < frame.bitmap.height else { return }
        accept(frame, overlap: frame.bitmap.height - newRows, up: up)
        keptPosition = trackedPosition
    }

    /// Signed shift of `current` against `previous`: positive when the
    /// content moved up (the page scrolled down). Searches near `predicted`
    /// first, then everywhere; nil when nothing matches.
    private func trackShift(previous: BitmapData, current: BitmapData, predicted: Int) -> Int? {
        let height = min(previous.height, current.height)
        let width = min(previous.width, current.width) - scrollbarWidthPx
        let bands = staticBands(previous: previous, current: current)
        var top = bands.top, bottom = height - bands.bottom
        if bottom - top < 64 { top = 0; bottom = height }
        let rows = bottom - top
        let columnCount = 96
        guard rows > 48, width > columnCount else { return nil }
        let columns = (0..<columnCount).map { 2 + $0 * (width - 4) / columnCount }
        func gray(_ p: (r: UInt8, g: UInt8, b: UInt8)) -> Int { (Int(p.r) + 2 * Int(p.g) + Int(p.b)) / 4 }
        func samples(_ bitmap: BitmapData) -> [UInt8] {
            var out = [UInt8](repeating: 0, count: rows * columnCount)
            for row in 0..<rows {
                for (i, x) in columns.enumerated() {
                    out[row * columnCount + i] = UInt8(gray(bitmap.pixel(x: x, y: top + row)))
                }
            }
            return out
        }
        let prev = samples(previous), cur = samples(current)
        let textured: [Bool] = (0..<rows).map { row in
            let slice = cur[(row * columnCount)..<((row + 1) * columnCount)]
            return Int(slice.max()!) - Int(slice.min()!) > 24
        }
        let minimumRows = 12, maxShift = rows - 24

        func score(_ shift: Int, giveUpAbove limit: Double = .infinity) -> Double? {
            var diff = 0, counted = 0
            for row in max(0, -shift)..<min(rows, rows - shift) where textured[row] {
                let a = (row + shift) * columnCount, b = row * columnCount
                for i in 0..<columnCount { diff += abs(Int(prev[a + i]) - Int(cur[b + i])) }
                counted += 1
                if counted >= minimumRows, Double(diff) / Double(counted * columnCount) > limit * 2 + 4 { return nil }
            }
            guard counted >= minimumRows else { return nil }
            return Double(diff) / Double(counted * columnCount)
        }
        func denseScore(_ shift: Int) -> Double {
            var diff = 0, counted = 0
            for row in max(0, -shift)..<min(rows, rows - shift) where textured[row] {
                var x = 0
                while x < width {
                    diff += abs(gray(previous.pixel(x: x, y: top + row + shift)) - gray(current.pixel(x: x, y: top + row)))
                    x += 2
                }
                counted += 1
            }
            return counted > 0 ? Double(diff) / Double(counted * ((width + 1) / 2)) : .infinity
        }
        func pick(_ shifts: [Int]) -> (shift: Int, score: Double)? {
            var coarse: [(Int, Double)] = []
            var best = Double.infinity
            for shift in shifts {
                if let value = score(shift, giveUpAbove: best) {
                    coarse.append((shift, value))
                    best = min(best, value)
                }
            }
            let ties = coarse.filter { $0.1 <= best + 2 }.sorted { $0.1 < $1.1 }.prefix(8)
            guard let first = ties.first else { return nil }
            if ties.count == 1 { return first }
            return ties.min { denseScore($0.0) < denseScore($1.0) }
        }

        // Near the last step: motion is continuous between stream frames.
        // Search every shift, nearest the predicted one first so a good match
        // is found early and the rest are cut short. A window around the
        // prediction alone took a shift off by one repeat of periodic text
        // (2026-10-28); the dense check among near-ties tells them apart.
        let center = max(-maxShift, min(maxShift, predicted))
        var order = [center]
        for distance in 1...(2 * maxShift) {
            if center + distance <= maxShift { order.append(center + distance) }
            if center - distance >= -maxShift { order.append(center - distance) }
        }
        guard let any = pick(order), any.score <= 10 else {
            FileLog.write("scroll capture track miss: predicted \(predicted)")
            return nil
        }
        return any.shift
    }

    /// Accepts or rejects one captured frame against the last accepted one.
    private func consider(_ image: NSImage, minimumNewFraction: Double = 1.0 / 200) -> FrameOutcome {
        guard frames.count < maxFrames else { return .atFrameLimit }
        guard let bitmap = bitmapData(from: image) else {
            rejectedNoImage += 1
            return .noNewContent
        }

        let candidateFrame = CapturedFrame(image: image, bitmap: bitmap)

        if let previousFrame = frames.last,
           imagesAreNearlyIdentical(previousFrame.bitmap, candidateFrame.bitmap) {
            rejectedIdentical += 1
            return .noNewContent
        }

        guard let previousFrame = frames.last else {
            frames.append(candidateFrame)
            initPreview(from: candidateFrame)
            return .appended
        }

        let minimumNewRows = max(8, Int(Double(candidateFrame.bitmap.height) * minimumNewFraction))
        var step = measureStep(from: previousFrame, to: candidateFrame, minimumNewRows: minimumNewRows)
        if step.newRows == 0, let pending = pendingFrame {
            // Lost contact with the last accepted frame: the pending one is
            // closer, so take it and measure again from there.
            pendingFrame = nil
            accept(pending.frame, overlap: pending.overlap, up: pending.up)
            guard frames.count < maxFrames else { return .atFrameLimit }
            step = measureStep(from: pending.frame, to: candidateFrame, minimumNewRows: minimumNewRows)
        }
        let previousForDiagnostics = frames.last ?? previousFrame
        guard step.newRows >= minimumNewRows else {
            if step.newRows > 0 {
                pendingFrame = (candidateFrame, candidateFrame.bitmap.height - step.newRows, step.up)
            }
            rejectedSmallShift += 1
            lastRejectedOverlap = (candidateFrame.bitmap.height - step.newRows, candidateFrame.bitmap.height)
            // Keep the first few rejected pairs so the miss can be studied
            // offline. Local only; the folder is overwritten each session.
            if step.newRows == 0, rejectedSmallShift <= 3, Defaults.keepsCaptureDiagnostics {
                let dir = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Library/Logs/Clip/scroll-misses", isDirectory: true)
                if rejectedSmallShift == 1 { try? FileManager.default.removeItem(at: dir) }
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                for (name, frame) in [("prev", previousForDiagnostics), ("cur", candidateFrame)] {
                    if let data = frame.image.pngDataPreservingBacking() {
                        try? data.write(to: dir.appendingPathComponent("\(rejectedSmallShift)-\(name).png"))
                    }
                }
            }
            return step.newRows == 0 ? .noOverlap : .noNewContent
        }

        pendingFrame = nil
        accept(candidateFrame, overlap: candidateFrame.bitmap.height - step.newRows, up: step.up)
        return .appended
    }

    /// New rows `candidate` adds next to `previous`, and whether it sits above
    /// it. Zero when they don't overlap or nothing moved.
    private func measureStep(
        from previous: CapturedFrame, to candidate: CapturedFrame, minimumNewRows: Int
    ) -> (newRows: Int, up: Bool) {
        let height = candidate.bitmap.height
        var down = 0, downScore = Double.infinity
        if scrollsUp != true {
            down = height - findOverlap(previous: previous.bitmap, current: candidate.bitmap)
            downScore = down > 0 ? lastMatchScore : .infinity
            // Once the direction is known, or a near-exact match settles it.
            if scrollsUp == false || (down >= minimumNewRows && downScore < 2) { return (down, false) }
        }
        // The candidate may sit above the previous frame. Before the direction
        // is known, take whichever side matches better: on repetitive content
        // a loose downward match once locked an upward scroll the wrong way.
        let up = height - findOverlap(previous: candidate.bitmap, current: previous.bitmap)
        let upScore = up > 0 ? lastMatchScore : .infinity
        if scrollsUp == true { return (up, true) }
        if up > 0, upScore < downScore { return (up, true) }
        return (down, false)
    }

    private func accept(_ frame: CapturedFrame, overlap: Int, up: Bool) {
        if scrollsUp == nil { scrollsUp = up }
        FileLog.write("scroll capture frame \(frames.count + 1) overlap=\(overlap) new=\(frame.bitmap.height - overlap) of \(frame.bitmap.height)px\(up ? " up" : "")")
        frames.append(frame)
        overlaps.append(overlap)
        if up {
            // Growing upward: re-stitch for the thumbnail instead of appending.
            if let image = stitchAcceptedFrames() {
                DispatchQueue.main.async { [weak self] in self?.onPreviewUpdated?(image) }
            }
        } else {
            appendToPreview(frame.bitmap, overlapPixels: overlap)
        }
    }

    // MARK: - Incremental Preview

    private func initPreview(from frame: CapturedFrame) {
        previewScale = CGFloat(frame.bitmap.height) / max(frame.image.size.height, 1)
        previewPointWidth = frame.image.size.width

        let initialCapacity = frame.bitmap.height * 10
        guard let output = makeOutputBitmap(
            from: frame.bitmap,
            totalHeightPixels: initialCapacity
        ) else { return }

        copyRows(
            from: frame.bitmap,
            sourceStartRow: 0,
            rowCount: frame.bitmap.height,
            to: output,
            destinationStartRow: 0
        )

        previewBitmap = output
        previewHeightPixels = frame.bitmap.height
        emitPreviewImage()
    }

    private func appendToPreview(_ bitmap: BitmapData, overlapPixels: Int) {
        guard var previewBitmap else { return }

        let newRows = bitmap.height - overlapPixels
        guard newRows > 0 else { return }
        // A sticky footer would otherwise repeat between every appended band:
        // drop it from the first frame once and take new rows from above it.
        let footer = min(stickyFooterPx ?? 0, max(0, bitmap.height - newRows))
        if footer > 0, !previewFooterTrimmed {
            previewHeightPixels = max(0, previewHeightPixels - footer)
            previewFooterTrimmed = true
        }
        let sourceStart = previewFooterTrimmed ? bitmap.height - footer - newRows : overlapPixels

        let neededHeight = previewHeightPixels + newRows
        if neededHeight > previewBitmap.height {
            let newCapacity = neededHeight + bitmap.height * 5
            guard let grown = makeOutputBitmap(
                from: bitmap,
                totalHeightPixels: newCapacity
            ) else { return }
            copyRows(
                from: previewBitmap,
                sourceStartRow: 0,
                rowCount: previewHeightPixels,
                to: grown,
                destinationStartRow: 0
            )
            self.previewBitmap = grown
            previewBitmap = grown
        }

        copyRows(
            from: bitmap,
            sourceStartRow: sourceStart,
            rowCount: newRows,
            to: previewBitmap,
            destinationStartRow: previewHeightPixels
        )

        previewHeightPixels += newRows
        emitPreviewImage()
    }

    private func emitPreviewImage() {
        guard let previewBitmap, previewHeightPixels > 0 else { return }

        let totalHeightPoints = CGFloat(previewHeightPixels) / previewScale
        guard let image = previewBitmap.makeImage(
            pointSize: NSSize(width: previewPointWidth, height: totalHeightPoints),
            pixelHeight: previewHeightPixels
        ) else { return }

        DispatchQueue.main.async { [weak self] in
            guard self != nil else { return }
            self?.onPreviewUpdated?(image)
        }
    }

    // MARK: - Final Stitch

    private func stitchAcceptedFrames() -> NSImage? {
        // Top to bottom, whichever way the user scrolled.
        let frames = scrollsUp == true ? Array(self.frames.reversed()) : self.frames
        let overlaps = scrollsUp == true ? Array(self.overlaps.reversed()) : self.overlaps
        guard let firstFrame = frames.first else { return nil }

        let bitmapHeight = firstFrame.bitmap.height
        let scale = CGFloat(bitmapHeight) / max(firstFrame.image.size.height, 1)

        // Content above a sticky footer is stitched; the footer itself is
        // added once, from the last frame, at the very end.
        let newRowsPerFrame = overlaps.map { bitmapHeight - $0 }
        let footer = min(stickyFooterPx ?? 0, max(0, bitmapHeight - (newRowsPerFrame.max() ?? 0)))
        let contentHeight = bitmapHeight - footer
        let totalHeightPixels = newRowsPerFrame.reduce(bitmapHeight, +)
        let totalHeightPoints = CGFloat(totalHeightPixels) / scale

        guard let stitchedBitmap = makeOutputBitmap(
            from: firstFrame.bitmap,
            totalHeightPixels: totalHeightPixels
        ) else {
            return firstFrame.image
        }

        var destinationRow = 0

        for index in frames.indices {
            let sourceStartRow = index == 0 ? 0 : contentHeight - newRowsPerFrame[index - 1]
            let rowsToCopy = index == 0 ? contentHeight : newRowsPerFrame[index - 1]

            copyRows(
                from: frames[index].bitmap,
                sourceStartRow: sourceStartRow,
                rowCount: rowsToCopy,
                to: stitchedBitmap,
                destinationStartRow: destinationRow
            )

            destinationRow += rowsToCopy
        }
        if footer > 0, let last = frames.last {
            copyRows(
                from: last.bitmap,
                sourceStartRow: contentHeight,
                rowCount: footer,
                to: stitchedBitmap,
                destinationStartRow: destinationRow
            )
        }

        return stitchedBitmap.makeImage(
            pointSize: NSSize(width: firstFrame.image.size.width, height: totalHeightPoints),
            pixelHeight: totalHeightPixels
        )
    }

    // MARK: - Overlap Detection

    /// Computes how many rows at the top of `current` overlap with the bottom of
    /// `previous`, using Apple Vision's translational image registration. Vision
    /// is significantly more accurate than per-row pixel matching on content
    /// where neighbouring rows look nearly identical (text, code, chat logs):
    /// it considers the whole image as a 2D signal rather than scoring rows
    /// independently, so it doesn't snap to wrong-but-locally-plausible offsets.
    ///
    /// The returned value is in pixels and lies in
    /// `0...min(previous.height, current.height)`.
    private func findOverlap(
        previous: BitmapData,
        current: BitmapData
    ) -> Int {
        let height = min(previous.height, current.height)
        guard height > 0 else { return 0 }

        // One-time scrollbar detection on the first usable frame pair.
        // Once cached, the right `scrollbarWidthPx` columns of every frame
        // are kept out of Vision's view to stop the moving slider from
        // poisoning the translation estimate.
        if !scrollbarDetected {
            detectScrollbar(current: current, previous: previous)
        }

        guard let previousCG = previous.makeCGImage(pixelHeight: previous.height),
              let currentCG = current.makeCGImage(pixelHeight: current.height) else {
            return height
        }

        // Crop sticky-UI regions out of the Vision inputs. The X crop is
        // safe because Vision measures Y translation independently per
        // column. The Y crop is safe because both images get the same
        // top trimmed — the residual Y shift Vision reports is therefore
        // the shift of post-header content, which is exactly the scroll
        // distance we want.
        // Use the common extent (min of both CGImages) so the crop is
        // always in-bounds for both — guarantees `cropping(to:)`
        // succeeds and Vision sees same-sized inputs.
        let commonWidth = min(currentCG.width, previousCG.width)
        let commonHeight = min(currentCG.height, previousCG.height)
        let cropWidth = max(0, commonWidth - scrollbarWidthPx)
        // Rows identical in both frames at the top and bottom are fixed UI
        // (status bar, navigation bar, tab bar). Left in, they outvote the
        // scrolled content and Vision reports no movement at all, which made
        // every iPhone Mirroring frame look unscrolled (2026-10-27).
        let bands = staticBands(previous: previous, current: current)
        let learnedHeader = stickyHeaderDetectionDone ? min(stickyHeaderPx, commonHeight / 5) : 0
        var cropY = max(learnedHeader, bands.top)
        var cropBottom = bands.bottom
        if commonHeight - cropY - cropBottom < 50 {
            cropY = learnedHeader
            cropBottom = 0
        }
        let cropHeight = commonHeight - cropY - cropBottom

        let visionPrevious: CGImage
        let visionCurrent: CGImage
        if cropWidth >= 50 && cropHeight >= 50 && (scrollbarWidthPx > 0 || cropY > 0 || cropBottom > 0) {
            let cropRect = CGRect(x: 0, y: cropY, width: cropWidth, height: cropHeight)
            visionPrevious = previousCG.cropping(to: cropRect) ?? previousCG
            visionCurrent = currentCG.cropping(to: cropRect) ?? currentCG
        } else {
            visionPrevious = previousCG
            visionCurrent = currentCG
        }

        let request = VNTranslationalImageRegistrationRequest(targetedCGImage: visionPrevious)
        let handler = VNImageRequestHandler(cgImage: visionCurrent, options: [:])

        do {
            try handler.perform([request])
        } catch {
            return height
        }

        guard let observation = request.results?.first as? VNImageTranslationAlignmentObservation else {
            return height
        }

        // alignmentTransform.ty is the pixel distance the source (current frame)
        // must be shifted to align with the target (previous frame). For a page
        // that scrolled DOWN between frames, this comes out positive and equals
        // the height of newly-revealed content at the bottom of `current`.
        // Because both Vision inputs were cropped identically, ty is the same
        // shift we would see in the original frame coordinates — apply directly.
        let visionShift = Int(observation.alignmentTransform.ty.rounded())
        var newContentPx = visionShift
        if visionShift > 0 {
            // No shift matches: the frames don't overlap, so taking this one
            // would splice unrelated content.
            guard let refined = refinedShift(previous: previous, current: current, estimate: visionShift,
                                             top: cropY, bottom: height - cropBottom, width: cropWidth)
            else { return height }
            newContentPx = refined
        }

        // First time we see a real shift, try to learn where the sticky
        // header ends so subsequent frames can crop it out.
        if newContentPx > 5 && !stickyHeaderDetectionDone {
            detectStickyHeader(current: current, previous: previous)
        }

        guard newContentPx > 0 else { return height }
        // The scrolled content can't have moved further than the area between
        // the fixed bands; a larger answer is a mismatch, not a scroll.
        guard newContentPx < height - cropY - cropBottom else { return height }
        stickyFooterPx = min(stickyFooterPx ?? cropBottom, cropBottom)

        let overlap = height - newContentPx
        return max(0, min(height, overlap))
    }

    /// Vision's estimate can be off by whole lines on dark, line-structured
    /// content such as terminals, which duplicated or cut text at the seams
    /// (2026-10-28). Score every shift by how well the overlapping rows match,
    /// counting only rows with visible detail so blank areas can't vote, and
    /// keep Vision's answer unless another shift matches clearly better.
    /// Compares rows `top..<bottom`.
    private func refinedShift(
        previous: BitmapData, current: BitmapData, estimate: Int,
        top: Int, bottom: Int, width: Int
    ) -> Int? {
        let rows = bottom - top
        let columnCount = 96
        lastMatchScore = .infinity
        guard rows > 32, width > columnCount else { return estimate }
        let columns = (0..<columnCount).map { 2 + $0 * (width - 4) / columnCount }
        func samples(_ bitmap: BitmapData) -> [UInt8] {
            var out = [UInt8](repeating: 0, count: rows * columnCount)
            for row in 0..<rows {
                for (i, x) in columns.enumerated() {
                    let p = bitmap.pixel(x: x, y: top + row)
                    out[row * columnCount + i] = UInt8((Int(p.r) + 2 * Int(p.g) + Int(p.b)) / 4)
                }
            }
            return out
        }
        let prev = samples(previous), cur = samples(current)
        let textured: [Bool] = (0..<rows).map { row in
            let slice = cur[(row * columnCount)..<((row + 1) * columnCount)]
            return Int(slice.max()!) - Int(slice.min()!) > 24
        }

        let minimumTexturedRows = 12
        func score(_ shift: Int, giveUpAbove limit: Double = .infinity) -> Double? {
            var diff = 0, counted = 0
            for row in 0..<(rows - shift) where textured[row] {
                let a = (row + shift) * columnCount, b = row * columnCount
                for i in 0..<columnCount { diff += abs(Int(prev[a + i]) - Int(cur[b + i])) }
                counted += 1
                if counted >= minimumTexturedRows, Double(diff) / Double(counted * columnCount) > limit * 2 + 4 {
                    return nil
                }
            }
            guard counted >= minimumTexturedRows else { return nil }
            return Double(diff) / Double(counted * columnCount)
        }

        // The 96 sampled columns can step over narrow details such as line
        // numbers, so on repetitive text a shift off by whole blocks of lines
        // scored as exact and those lines vanished (2026-10-28). Confirm
        // near-ties against every second column.
        func denseScore(_ shift: Int) -> Double {
            var diff = 0, counted = 0
            for row in 0..<(rows - shift) where textured[row] {
                var x = 0
                while x < width {
                    let a = previous.pixel(x: x, y: top + row + shift), b = current.pixel(x: x, y: top + row)
                    diff += abs((Int(a.r) + 2 * Int(a.g) + Int(a.b)) / 4 - (Int(b.r) + 2 * Int(b.g) + Int(b.b)) / 4)
                    x += 2
                }
                counted += 1
            }
            return counted > 0 ? Double(diff) / Double(counted * ((width + 1) / 2)) : .infinity
        }

        let estimateScore = estimate < rows ? score(estimate) : nil
        // A near-exact match on both checks can't be beaten; skip the search.
        if let estimateScore, estimateScore < 2, denseScore(estimate) < 2 {
            lastMatchScore = estimateScore
            return estimate
        }
        var coarse: [Int: Double] = [:]
        if let estimateScore { coarse[estimate] = estimateScore }
        var bestCoarse = estimateScore ?? .infinity
        for shift in 1..<rows where shift != estimate {
            if let candidate = score(shift, giveUpAbove: bestCoarse) {
                coarse[shift] = candidate
                bestCoarse = min(bestCoarse, candidate)
            }
        }
        let nearTies = coarse.filter { $0.value <= bestCoarse + 2 }.sorted { $0.value < $1.value }.prefix(8)
        let best = nearTies.count > 1
            ? nearTies.min { denseScore($0.key) < denseScore($1.key) }?.key ?? estimate
            : nearTies.first?.key ?? estimate
        let bestScore = coarse[best] ?? .infinity
        // Take another shift only when it matches near-exactly or much better
        // than Vision; compressed sources (iPhone Mirroring) never match
        // exactly anywhere. When nothing matches, there is no overlap.
        let visionScore = estimateScore ?? .infinity
        guard bestScore < 3 || bestScore < visionScore * 0.5 else {
            if min(bestScore, visionScore) > 10 {
                FileLog.write("scroll capture no overlap: vision \(estimate) score \(String(format: "%.1f", visionScore)), best \(best) score \(String(format: "%.1f", bestScore))")
                return nil
            }
            lastMatchScore = visionScore
            return estimate
        }
        FileLog.write("scroll capture refined shift \(estimate) -> \(best) score \(estimateScore.map { String(format: "%.1f", $0) } ?? "-") -> \(String(format: "%.1f", bestScore))")
        lastMatchScore = bestScore
        return best
    }

    // MARK: - Sticky element detection

    /// Counts rows at the top and bottom that are the same in both frames.
    /// Each band is capped at 40% of the height so a mostly-blank page can't
    /// swallow the content area.
    private func staticBands(previous: BitmapData, current: BitmapData) -> (top: Int, bottom: Int) {
        let width = min(previous.width, current.width)
        let height = min(previous.height, current.height)
        guard width > 40, height > 40 else { return (0, 0) }
        let inset = width / 20
        func rowIsStatic(_ y: Int) -> Bool {
            var diff = 0, samples = 0
            var x = inset
            while x < width - inset {
                let a = previous.pixel(x: x, y: y), b = current.pixel(x: x, y: y)
                diff += abs(Int(a.r) - Int(b.r)) + abs(Int(a.g) - Int(b.g)) + abs(Int(a.b) - Int(b.b))
                samples += 1
                x += 3
            }
            // Mirrored and video-backed content is compressed, so fixed rows
            // still differ by a few levels between frames.
            return samples > 0 && Double(diff) / Double(samples * 3) <= 6
        }
        // Tolerate short changing runs inside a fixed bar (a home indicator,
        // a translucent edge); a band ends after 12 changed rows in a row.
        func band(_ rowAt: (Int) -> Int) -> Int {
            var lastStatic = -1, changedRun = 0
            for i in 0..<(height * 2 / 5) {
                if rowIsStatic(rowAt(i)) {
                    lastStatic = i
                    changedRun = 0
                } else {
                    changedRun += 1
                    if changedRun > 12 { break }
                }
            }
            return lastStatic + 1
        }
        return (band { $0 }, band { height - 1 - $0 })
    }

    /// Scans the right edge of the frame pair looking for columns whose
    /// pixels differ between the two captures. Those columns are where the
    /// scrollbar slider lives — it moves while the page scrolls, while
    /// page content shifts vertically. Identifying and cropping it out
    /// keeps Vision from anchoring on the slider's bounding box.
    private func detectScrollbar(current: BitmapData, previous: BitmapData) {
        defer { scrollbarDetected = true }

        let width = min(current.width, previous.width)
        let height = min(current.height, previous.height)
        guard width > 80, height > 40 else { return }

        let maxScan = min(50, width / 8)
        let sampleStart = height / 5
        let sampleEnd = (height * 4) / 5
        let sampleStep = max(1, (sampleEnd - sampleStart) / 30)

        var detectedWidth = 0
        var sawQuietAfterMoving = false

        for offset in 0..<maxScan {
            let column = width - 1 - offset
            var totalDiff = 0
            var samples = 0

            var row = sampleStart
            while row < sampleEnd {
                let lhs = current.pixel(x: column, y: row)
                let rhs = previous.pixel(x: column, y: row)
                totalDiff +=
                    abs(Int(lhs.r) - Int(rhs.r)) +
                    abs(Int(lhs.g) - Int(rhs.g)) +
                    abs(Int(lhs.b) - Int(rhs.b))
                samples += 1
                row += sampleStep
            }

            guard samples > 0 else { continue }
            let avg = totalDiff / samples

            if avg > 8 {
                detectedWidth = offset + 1
            } else if detectedWidth > 0 {
                // First quiet column past the moving region — scrollbar
                // edge found, stop scanning.
                sawQuietAfterMoving = true
                break
            }
        }

        // Only commit a width if the scan actually observed a moving →
        // quiet transition at the edge. Without that boundary, the
        // "moving" region might just be content (e.g., an animation
        // taking up the whole right area), not a scrollbar.
        if sawQuietAfterMoving && detectedWidth >= 3 && detectedWidth <= 40 {
            // Small buffer past the detected edge to absorb anti-aliasing
            // fringe and any 1–2 px misalignment in our column sampling.
            scrollbarWidthPx = detectedWidth + 4
        }
    }

    /// Scans top-to-bottom looking for the first row that genuinely differs
    /// between the two captures. Rows above that boundary held identical
    /// pixels in both frames, which is the signature of a sticky element
    /// (top nav bar, toolbar, banner). Multiple samples are required to
    /// agree before the value is locked in — a single observation could
    /// be coincidental on a content-light page.
    private func detectStickyHeader(current: BitmapData, previous: BitmapData) {
        let width = min(current.width, previous.width)
        let height = min(current.height, previous.height)
        guard width > 80, height > 40 else {
            stickyHeaderDetectionDone = true
            return
        }

        // Exclude the right margin (scrollbar) from sampling so its
        // motion doesn't fool the per-row diff into thinking a header
        // row is non-sticky.
        let scanWidth = max(40, width - scrollbarWidthPx)
        let columnStart = width / 10
        let columnEnd = min(scanWidth - 1, (scanWidth * 9) / 10)
        let columnStep = max(1, (columnEnd - columnStart) / 20)

        var firstMovingRow = -1
        for row in 0..<height {
            var totalDiff = 0
            var samples = 0

            var column = columnStart
            while column <= columnEnd {
                let lhs = current.pixel(x: column, y: row)
                let rhs = previous.pixel(x: column, y: row)
                totalDiff +=
                    abs(Int(lhs.r) - Int(rhs.r)) +
                    abs(Int(lhs.g) - Int(rhs.g)) +
                    abs(Int(lhs.b) - Int(rhs.b))
                samples += 1
                column += columnStep
            }

            guard samples > 0 else { continue }
            if totalDiff / samples > 8 {
                firstMovingRow = row
                break
            }
        }

        guard firstMovingRow >= 0 else {
            // Whole frame is frozen — page didn't actually scroll. Don't
            // make any decision yet; wait for a later frame pair.
            return
        }

        let frozenRows = firstMovingRow
        let maxPlausibleHeader = (height * 6) / 10  // 60% of height

        stickyHeaderSamplesTaken += 1

        if frozenRows < 10 {
            // Too small to be a real sticky element. Lock in "no header".
            stickyHeaderPx = 0
            stickyHeaderDetectionDone = true
            return
        }

        if frozenRows > maxPlausibleHeader {
            // Implausibly large frozen region — give up rather than
            // chop away real content.
            stickyHeaderPx = 0
            stickyHeaderDetectionDone = true
            return
        }

        if stickyHeaderSamplesTaken == 1 {
            stickyHeaderPx = frozenRows
        } else if abs(frozenRows - stickyHeaderPx) <= 5 {
            stickyHeaderPx = min(stickyHeaderPx, frozenRows)
        } else {
            // Sample disagrees with the previous one by too much.
            // Detection isn't stable on this page; bail out without
            // applying any header crop.
            stickyHeaderPx = 0
            stickyHeaderDetectionDone = true
            return
        }

        // Two consistent samples is enough to commit.
        if stickyHeaderSamplesTaken >= 2 {
            stickyHeaderDetectionDone = true
        }
    }

    // MARK: - Image Helpers

    private func imagesAreNearlyIdentical(_ lhs: BitmapData, _ rhs: BitmapData) -> Bool {
        guard lhs.width == rhs.width, lhs.height == rhs.height else {
            return false
        }

        let numCols = min(32, max(16, lhs.width / 20))
        let numRows = min(32, max(16, lhs.height / 20))
        let sampleCols = sampledColumns(width: lhs.width, count: numCols)
        let sampleRows = sampledRows(height: lhs.height, count: numRows)

        var diff = 0
        var comparisons = 0

        for row in sampleRows {
            for col in sampleCols {
                diff += pixelDiff(lhs.pixel(x: col, y: row), rhs.pixel(x: col, y: row))
                comparisons += 1
            }
        }

        guard comparisons > 0 else { return false }
        return diff / comparisons < 3
    }

    private func sampledColumns(width: Int, count: Int) -> [Int] {
        guard width > 0, count > 0 else { return [] }

        let inset = min(max(4, width / 12), max(4, width / 4))
        let lowerBound = min(width - 1, inset)
        let upperBound = max(lowerBound, width - inset - 1)
        let span = max(1, upperBound - lowerBound + 1)

        var result: [Int] = []
        result.reserveCapacity(count)

        for index in 0..<count {
            let column = lowerBound + min(span - 1, span * (index * 2 + 1) / max(1, count * 2))
            if result.last != column {
                result.append(column)
            }
        }

        return result
    }

    private func sampledRows(height: Int, count: Int) -> [Int] {
        guard height > 0, count > 0 else { return [] }

        var rows: [Int] = []
        rows.reserveCapacity(count)

        for index in 0..<count {
            let row = min(height - 1, height * (index * 2 + 1) / max(1, count * 2))
            if rows.last != row {
                rows.append(row)
            }
        }

        return rows
    }

    private func pixelDiff(_ lhs: (r: UInt8, g: UInt8, b: UInt8), _ rhs: (r: UInt8, g: UInt8, b: UInt8)) -> Int {
        abs(Int(lhs.r) - Int(rhs.r)) +
        abs(Int(lhs.g) - Int(rhs.g)) +
        abs(Int(lhs.b) - Int(rhs.b))
    }

    private func bitmapData(from image: NSImage) -> BitmapData? {
        guard let rep = image.bitmapImageRepPreservingBacking() else { return nil }
        return BitmapData(rep: rep)
    }

    private func makeOutputBitmap(from source: BitmapData, totalHeightPixels: Int) -> BitmapData? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: source.width,
            pixelsHigh: totalHeightPixels,
            bitsPerSample: source.rep.bitsPerSample,
            samplesPerPixel: source.rep.samplesPerPixel,
            hasAlpha: source.rep.hasAlpha,
            isPlanar: false,
            colorSpaceName: source.rep.colorSpaceName,
            bitmapFormat: source.rep.bitmapFormat,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }

        return BitmapData(rep: rep, format: source.imageFormat)
    }

    private func copyRows(
        from source: BitmapData,
        sourceStartRow: Int,
        rowCount: Int,
        to destination: BitmapData,
        destinationStartRow: Int
    ) {
        guard rowCount > 0 else { return }

        let bytesPerRow = min(source.width * source.bytesPerPixelValue, min(source.bytesPerRow, destination.bytesPerRow))

        for rowOffset in 0..<rowCount {
            let sourceOffset = (sourceStartRow + rowOffset) * source.bytesPerRow
            let destinationOffset = (destinationStartRow + rowOffset) * destination.bytesPerRow
            memcpy(
                destination.data.advanced(by: destinationOffset),
                source.data.advanced(by: sourceOffset),
                bytesPerRow
            )
        }
    }

    private final class BitmapData {
        let rep: NSBitmapImageRep
        let data: UnsafeMutablePointer<UInt8>
        let bytesPerRow: Int
        let width: Int
        let height: Int
        let imageFormat: ImageFormat
        private let bytesPerPixel: Int

        init?(rep: NSBitmapImageRep, format: ImageFormat? = nil) {
            guard let data = rep.bitmapData else { return nil }

            let resolvedFormat: ImageFormat
            if let format {
                resolvedFormat = format
            } else {
                let cgImage = rep.cgImage
                guard
                    let cgImage,
                    let colorSpace = cgImage.colorSpace
                else {
                    return nil
                }

                resolvedFormat = ImageFormat(
                    bitsPerComponent: cgImage.bitsPerComponent,
                    bitsPerPixel: cgImage.bitsPerPixel,
                    bitmapInfo: cgImage.bitmapInfo,
                    colorSpace: colorSpace
                )
            }

            self.rep = rep
            self.data = data
            self.bytesPerRow = rep.bytesPerRow
            self.width = rep.pixelsWide
            self.height = rep.pixelsHigh
            self.imageFormat = resolvedFormat
            self.bytesPerPixel = max(1, rep.bitsPerPixel / 8)
        }

        func pixel(x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
            guard x >= 0, x < width, y >= 0, y < height else {
                return (0, 0, 0)
            }

            let offset = y * bytesPerRow + x * bytesPerPixel
            return (data[offset], data[offset + 1], data[offset + 2])
        }

        func makeImage(pointSize: NSSize, pixelHeight: Int) -> NSImage? {
            guard let cgImage = makeCGImage(pixelHeight: pixelHeight) else { return nil }
            return NSImage(cgImage: cgImage, size: pointSize)
        }

        /// Builds a CGImage covering the top `pixelHeight` rows of this bitmap.
        /// Shared by `makeImage(pointSize:pixelHeight:)` (the preview/output
        /// pipeline) and by `findOverlap` (Apple Vision input).
        func makeCGImage(pixelHeight: Int) -> CGImage? {
            guard pixelHeight > 0, pixelHeight <= height else { return nil }

            let byteCount = pixelHeight * bytesPerRow
            let buffer = UnsafeBufferPointer(start: data, count: byteCount)
            let imageData = Data(buffer: buffer)

            guard let provider = CGDataProvider(data: imageData as CFData) else { return nil }
            return CGImage(
                width: width,
                height: pixelHeight,
                bitsPerComponent: imageFormat.bitsPerComponent,
                bitsPerPixel: imageFormat.bitsPerPixel,
                bytesPerRow: bytesPerRow,
                space: imageFormat.colorSpace,
                bitmapInfo: imageFormat.bitmapInfo,
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            )
        }

        var bytesPerPixelValue: Int { bytesPerPixel }
    }
}
