import AppKit
import ImageIO
@preconcurrency import Vision
import VisionKit

struct RecognizedTextToken: Equatable {
    let text: String
    /// Vision-normalized rectangle with bottom-left origin.
    let boundingBox: CGRect
}

struct RecognizedTextLine: Equatable {
    let text: String
    /// Vision-normalized rectangle with bottom-left origin.
    let boundingBox: CGRect
    let tokens: [RecognizedTextToken]

    init(text: String, boundingBox: CGRect, tokens: [RecognizedTextToken] = []) {
        self.text = text
        self.boundingBox = boundingBox
        self.tokens = tokens
    }
}

/// OCR routing plus Apple recognition helpers. Native Live Text remains
/// exclusive to Apple results so it cannot replace another provider's text.
/// Recognize and copy, with toasts. Shared by the toolbar button, the
/// text-recognition shortcut and the copy-image-text shortcut.
enum OCRActions {
    static func copyText(from image: NSImage, screen: NSScreen, anchorRect: NSRect) {
        let centerAnchor = NSPoint(x: anchorRect.midX, y: anchorRect.midY)
        ToastWindow.show(message: L10n.copyImageTextCopying, on: screen, centerAnchor: centerAnchor, duration: 60)
        let hint = DispatchWorkItem {
            ToastWindow.show(message: L10n.ocrWarmingUp, on: screen, centerAnchor: centerAnchor, duration: 60)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: hint)
        Task { @MainActor in
            let text: String
            do {
                text = try await OCRService.recognizeResult(image: image).text
            } catch {
                hint.cancel()
                guard !Task.isCancelled else { return }
                ToastWindow.show(message: error.localizedDescription, on: screen, centerAnchor: centerAnchor, duration: 2.5)
                return
            }
            hint.cancel()
            guard !Task.isCancelled else { return }
            if text.isEmpty {
                ToastWindow.show(message: L10n.copyImageTextNoText, on: screen, centerAnchor: centerAnchor, duration: 1.5)
            } else {
                ClipboardManager.copyToClipboard(text: text)
                ToastWindow.show(message: L10n.copyImageTextCopied, on: screen, centerAnchor: centerAnchor, duration: 1.5)
            }
        }
    }

    /// Toolbar OCR and the text-recognition shortcut follow the setting.
    static func handleRecognition(image: NSImage, screen: NSScreen, anchorRect: NSRect) {
        switch Defaults.ocrResultBehavior {
        case .copy: copyText(from: image, screen: screen, anchorRect: anchorRect)
        case .panel: OCRPanel.presentTextRecognition(image: image, anchorRect: anchorRect, screen: screen)
        }
    }
}

enum OCRService {
    /// Languages come from the user's setting. Two models load in about a
    /// second on first use; five can take tens of seconds while the OS
    /// prepares them.
    private static var preferredRecognitionLanguages: [String] {
        Defaults.ocrLanguageSet.languages
    }

    /// Vision prepares its language models on first use in a process, which
    /// can take from one second to a minute. Running a tiny request at launch
    /// moves that cost away from the user's first capture.
    static func warmUp() {
        PPOCREngine.shared.warmUp()
        DispatchQueue.global(qos: .utility).async {
            let size = CGSize(width: 64, height: 32)
            guard let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fill(CGRect(origin: .zero, size: size))
            guard let cg = ctx.makeImage() else { return }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = preferredRecognitionLanguages
            let start = Date()
            try? VNImageRequestHandler(cgImage: cg, options: [:]).perform([request])
            FileLog.write(String(format: "OCR warm-up %.2fs languages=%@", Date().timeIntervalSince(start), preferredRecognitionLanguages.joined(separator: ",")))
        }
    }

    @MainActor
    static func recognizeResult(image: NSImage) async throws -> OCRResult {
        let kind = Defaults.ocrProviderKind
        let config = OCRConfigStore.load(kind)
        return try await recognizeResult(image: image, kind: kind, config: config)
    }

    static func recognizeResult(image: NSImage, kind: OCRProviderKind,
                                config: OCRProviderConfig) async throws -> OCRResult {
        try Task.checkCancellation()
        if kind == .apple {
            let lines = await recognizeLinesWithFallback(image: image)
            try Task.checkCancellation()
            if !lines.isEmpty { return OCRResult(lines: lines, provider: kind) }
            let analysis = await analyzeText(image: image)
            try Task.checkCancellation()
            return OCRResult(text: analysis?.transcript ?? "", provider: kind)
        }
        do {
            return try await AsyncDeadline.run(seconds: 65) {
                try await NetworkOCRProvider.recognize(image: image, kind: kind, config: config)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch is AsyncDeadline.TimedOut {
            throw OCRProviderError.timeout
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            if error.code == .timedOut { throw OCRProviderError.timeout }
            throw OCRProviderError.service(String(error.errorCode))
        } catch let error as OCRProviderError {
            throw error
        } catch {
            throw OCRProviderError.response
        }
    }

    /// Recognizes text in `image` and returns it as newline-joined lines,
    /// ordered top-to-bottom then left-to-right. Returns an empty string when
    /// nothing is found or the image cannot be decoded.
    static func recognize(image: NSImage) async -> String {
        let lines = await recognizeLines(image: image)
        guard !Task.isCancelled else { return "" }
        if !lines.isEmpty {
            return lines.map(\.text).joined(separator: "\n")
        }
        if let analysis = await analyzeText(image: image) {
            return analysis.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }

    /// Runs the same system Live Text analyzer used by Preview. The returned
    /// analysis can be attached to `ImageAnalysisOverlayView` for native text
    /// selection, menus, and keyboard copy.
    static func analyzeText(image: NSImage) async -> ImageAnalysis? {
        guard ImageAnalyzer.isSupported else { return nil }

        let configuration = ImageAnalyzer.Configuration(.text)

        do {
            let analysis = try await AsyncDeadline.run(seconds: 3) {
                let cgImage = await withCheckedContinuation { continuation in
                    DispatchQueue.global(qos: .userInitiated).async {
                        continuation.resume(returning: image.cgImage(
                            forProposedRect: nil, context: nil, hints: nil
                        ))
                    }
                }
                try Task.checkCancellation()
                guard let cgImage else { return nil as ImageAnalysis? }
                return try await ImageAnalyzer().analyze(
                    cgImage,
                    orientation: .up,
                    configuration: configuration
                )
            }
            return analysis?.hasResults(for: .text) == true ? analysis : nil
        } catch {
            return nil
        }
    }

    /// Vision first. The bundled PP-OCR model answers when Vision errors,
    /// finds nothing, or is still loading its language assets after 1.5 s
    /// (cold loads took 30 s or more on macOS 27.0.1, 2026-10-26).
    static func recognizeLinesWithFallback(image: NSImage) async -> [RecognizedTextLine] {
        let started = Date()
        switch Defaults.ocrEngine {
        case .system:
            return await recognizeLines(image: image)
        case .bundled:
            guard let cgImage = image.cgImagePreservingBacking() else { return [] }
            let lines = await Task.detached(priority: .userInitiated) { () -> [RecognizedTextLine] in
                do { return try PPOCREngine.shared.recognize(cgImage) } catch {
                    FileLog.write("OCR ppocr error=\(error)")
                    return []
                }
            }.value
            FileLog.write(String(format: "OCR ppocr-only %dx%d %.2fs lines=%d", cgImage.width, cgImage.height, Date().timeIntervalSince(started), lines.count))
            if lines.isEmpty { keepFailedInput(cgImage) }
            return lines
        case .auto:
            break
        }
        let vision = Task { await recognizeLines(image: image) }
        let early = try? await AsyncDeadline.run(seconds: 1.5) { await vision.value }
        if let early, !early.isEmpty {
            FileLog.write(String(format: "OCR chose vision %.2fs", Date().timeIntervalSince(started)))
            return early
        }
        guard PPOCREngine.shared.isAvailable, let cgImage = image.cgImagePreservingBacking() else {
            return await vision.value
        }
        let bundled = Task.detached(priority: .userInitiated) { () -> [RecognizedTextLine] in
            let start = Date()
            do {
                let lines = try PPOCREngine.shared.recognize(cgImage)
                FileLog.write(String(format: "OCR ppocr %dx%d %.2fs lines=%d", cgImage.width, cgImage.height, Date().timeIntervalSince(start), lines.count))
                return lines
            } catch {
                FileLog.write("OCR ppocr error=\(error)")
                return []
            }
        }
        let (lines, source) = await withTaskCancellationHandler {
            // Vision already finished empty: only the bundled model is left.
            // Otherwise take whichever of the two first returns text.
            if early != nil { return (await bundled.value, "ppocr") }
            return await firstNonEmpty(vision, bundled)
        } onCancel: {
            vision.cancel()
        }
        FileLog.write(String(format: "OCR chose %@ %.2fs lines=%d", source, Date().timeIntervalSince(started), lines.count))
        if lines.isEmpty { keepFailedInput(cgImage) }
        return lines
    }

    private static func firstNonEmpty(
        _ vision: Task<[RecognizedTextLine], Never>,
        _ bundled: Task<[RecognizedTextLine], Never>
    ) async -> ([RecognizedTextLine], String) {
        final class Race: @unchecked Sendable {
            private let lock = NSLock()
            private var pending = 2
            private var done = false
            /// True for the one arrival that should resume the caller.
            func arrive(found: Bool) -> Bool {
                lock.lock()
                defer { lock.unlock() }
                pending -= 1
                guard !done, found || pending == 0 else { return false }
                done = true
                return true
            }
        }
        let race = Race()
        return await withCheckedContinuation { continuation in
            for (task, name) in [(vision, "vision"), (bundled, "ppocr")] {
                Task {
                    let lines = await task.value
                    if race.arrive(found: !lines.isEmpty) { continuation.resume(returning: (lines, lines.isEmpty ? "none" : name)) }
                }
            }
        }
    }

    /// Keeps the last five images neither engine could read, next to the
    /// log, so a miss can be reproduced. Local only.
    private static func keepFailedInput(_ image: CGImage) {
        DispatchQueue.global(qos: .utility).async {
            let dir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Logs/Clip/ocr-misses", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let url = dir.appendingPathComponent("\(stamp).png")
            if let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) {
                CGImageDestinationAddImage(dest, image, nil)
                CGImageDestinationFinalize(dest)
            }
            let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            for old in files.filter({ $0.pathExtension == "png" }).sorted(by: { $0.lastPathComponent > $1.lastPathComponent }).dropFirst(5) {
                try? FileManager.default.removeItem(at: old)
            }
        }
    }

    /// Recognizes text in `image` and returns ordered text lines with their
    /// source rectangles so result panels can draw per-line copy targets.
    static func recognizeLines(image: NSImage) async -> [RecognizedTextLine] {
        let work = RecognitionWork()
        // Read results after synchronous perform returns. Its completion handler
        // can run before perform throws; resuming from both paths was unsafe.
        // Include image decoding and token assembly in the deadline as well.
        return (try? await AsyncDeadline.run(seconds: 90) {
            await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    DispatchQueue.global(qos: .userInitiated).async {
                        let lines = autoreleasepool { work.recognize(image: image) }
                        continuation.resume(returning: lines)
                    }
                }
            } onCancel: {
                work.cancel()
            }
        }) ?? []
    }

    private final class RecognitionWork: @unchecked Sendable {
        private let lock = NSLock()
        private var request: VNRecognizeTextRequest?
        private var cancelled = false

        func recognize(image: NSImage) -> [RecognizedTextLine] {
            guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                return []
            }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = OCRService.preferredRecognitionLanguages
            request.automaticallyDetectsLanguage = false
            let started = Date()
            var outcome = "lines=0"
            defer { FileLog.write(String(format: "OCR vision %dx%d %.2fs %@", cgImage.width, cgImage.height, Date().timeIntervalSince(started), outcome)) }

            lock.lock()
            guard !cancelled else { lock.unlock(); return [] }
            self.request = request
            lock.unlock()

            do {
                try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
                let lines = OCRService.assembleLines(request.results ?? [])
                outcome = "lines=\(lines.count)"
                return lines
            } catch {
                outcome = "error=\(error)"
                return []
            }
        }

        func cancel() {
            lock.lock()
            cancelled = true
            let request = self.request
            lock.unlock()
            request?.cancel()
        }
    }

    /// Orders observations into natural reading order. Vision bounding boxes
    /// are normalized with a bottom-left origin, so a larger `midY` means a
    /// higher line on screen.
    private static func assembleLines(_ observations: [VNRecognizedTextObservation]) -> [RecognizedTextLine] {
        let fragments: [RecognizedTextLine] = observations
            .compactMap { observation in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                let rawText = candidate.string
                guard let contentRange = rawText.nonWhitespaceRange else { return nil }
                let text = String(rawText[contentRange])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                return RecognizedTextLine(
                    text: text,
                    boundingBox: observation.boundingBox,
                    tokens: Self.tokens(in: rawText, contentRange: contentRange, candidate: candidate)
                )
            }
        return readingOrderLines(fragments)
    }

    /// Group by actual line height rather than a fixed fraction of the image.
    /// A fuzzy comparison inside `sorted` is not transitive, and emitting every
    /// observation on a new line turns widely spaced horizontal titles vertical.
    static func readingOrderLines(_ fragments: [RecognizedTextLine], joinsCJK: Bool = false) -> [RecognizedTextLine] {
        let sorted = fragments.sorted {
            if $0.boundingBox.midY != $1.boundingBox.midY {
                return $0.boundingBox.midY > $1.boundingBox.midY
            }
            return $0.boundingBox.minX < $1.boundingBox.minX
        }
        var rows: [[RecognizedTextLine]] = []
        for fragment in sorted {
            let box = fragment.boundingBox
            let matchingRow = rows.indices.filter { index in
                let reference = rows[index][0].boundingBox
                let height = min(box.height, reference.height)
                let overlap = min(box.maxY, reference.maxY) - max(box.minY, reference.minY)
                return height > 0 && overlap >= height * 0.5
                    && abs(box.midY - reference.midY) <= height * 0.5
            }.min { lhs, rhs in
                abs(rows[lhs][0].boundingBox.midY - box.midY)
                    < abs(rows[rhs][0].boundingBox.midY - box.midY)
            }
            if let matchingRow {
                rows[matchingRow].append(fragment)
            } else {
                rows.append([fragment])
            }
        }
        return rows.map { row in
            let ordered = row.sorted { $0.boundingBox.minX < $1.boundingBox.minX }
            var text = ordered[0].text
            var bounds = ordered[0].boundingBox
            for index in ordered.indices.dropFirst() {
                let previous = ordered[index - 1]
                let fragment = ordered[index]
                let characterWidth = max(
                    previous.boundingBox.width / CGFloat(max(previous.text.count, 1)),
                    fragment.boundingBox.width / CGFloat(max(fragment.text.count, 1))
                )
                let gap = fragment.boundingBox.minX - previous.boundingBox.maxX
                if gap > characterWidth * 3 {
                    text += "\t"
                } else if !(joinsCJK && previous.text.last?.isCJKLike == true
                            && fragment.text.first?.isCJKLike == true && gap < characterWidth * 0.75) {
                    text += " "
                }
                text += fragment.text
                bounds = bounds.union(fragment.boundingBox)
            }
            return RecognizedTextLine(
                text: text,
                boundingBox: bounds,
                tokens: ordered.flatMap(\.tokens)
            )
        }
    }

    private static func tokens(
        in rawText: String,
        contentRange: Range<String.Index>,
        candidate: VNRecognizedText
    ) -> [RecognizedTextToken] {
        var tokens: [RecognizedTextToken] = []
        var index = contentRange.lowerBound

        while index < contentRange.upperBound {
            if rawText[index].isWhitespace {
                index = rawText.index(after: index)
                continue
            }

            let start = index
            if rawText[index].isCJKLike {
                index = rawText.index(after: index)
            } else {
                repeat {
                    index = rawText.index(after: index)
                } while index < contentRange.upperBound
                    && !rawText[index].isWhitespace
                    && !rawText[index].isCJKLike
            }

            let range = start..<index
            guard let observation = try? candidate.boundingBox(for: range) else { continue }
            let text = String(rawText[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            tokens.append(RecognizedTextToken(text: text, boundingBox: observation.boundingBox))
        }

        return tokens
    }

}

private extension String {
    var nonWhitespaceRange: Range<String.Index>? {
        guard let first = firstIndex(where: { !$0.isWhitespace }),
              let last = lastIndex(where: { !$0.isWhitespace }) else {
            return nil
        }
        return first..<index(after: last)
    }
}

private extension Character {
    var isCJKLike: Bool {
        unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3040...0x30FF, // Hiragana + Katakana
                 0x3400...0x4DBF, // CJK Extension A
                 0x4E00...0x9FFF, // CJK Unified Ideographs
                 0xAC00...0xD7AF, // Hangul Syllables
                 0xF900...0xFAFF: // CJK Compatibility Ideographs
                return true
            default:
                return false
            }
        }
    }
}
