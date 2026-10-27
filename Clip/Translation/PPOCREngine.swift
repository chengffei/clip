import CoreGraphics
import CoreML
import Foundation

/// Bundled PP-OCRv6 small (Apache-2.0, PaddlePaddle) converted to Core ML.
/// Runs without the system's Vision language assets, so it still answers
/// when Vision is cold-loading or failing. Pre- and post-processing mirror
/// RapidOCR 3.10, the reference the conversion was checked against
/// (research/ocr-bench); boxes are axis-aligned, which screen text allows.
final class PPOCREngine: @unchecked Sendable {
    static let shared = PPOCREngine()

    private let lock = NSLock()
    private var loaded: (det: MLModel, rec: MLModel, characters: [String])?
    private var loadFailed = false

    /// Where the compiled models live: the app bundle, or the source tree
    /// when running tests.
    static var modelDirectory: URL? {
        if let env = ProcessInfo.processInfo.environment["CLIP_OCR_MODELS"] {
            return URL(fileURLWithPath: env)
        }
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("OCRModels"),
           FileManager.default.fileExists(atPath: bundled.path) {
            return bundled
        }
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/OCRModels")
        return FileManager.default.fileExists(atPath: source.path) ? source : nil
    }

    var isAvailable: Bool { Self.modelDirectory != nil }

    private func models() throws -> (det: MLModel, rec: MLModel, characters: [String]) {
        lock.lock()
        defer { lock.unlock() }
        if let loaded { return loaded }
        guard !loadFailed, let dir = Self.modelDirectory else { throw PPOCRError.unavailable }
        do {
            let config = MLModelConfiguration()
            // The GPU path aborts on large detector inputs (macOS 27.0.1).
            config.computeUnits = .cpuAndNeuralEngine
            let det = try MLModel(contentsOf: dir.appendingPathComponent("PPOCRv6Det.mlmodelc"), configuration: config)
            let rec = try MLModel(contentsOf: dir.appendingPathComponent("PPOCRv6Rec.mlmodelc"), configuration: config)
            let keys = try String(contentsOf: dir.appendingPathComponent("ppocrv6_keys.txt"), encoding: .utf8)
            // CTC index 0 is blank; the recognizer also appends a space.
            let characters = ["blank"] + keys.components(separatedBy: "\n") + [" "]
            let result = (det, rec, characters)
            loaded = result
            return result
        } catch {
            loadFailed = true
            throw error
        }
    }

    /// Loads both models off the main thread so the first capture is fast.
    func warmUp() {
        DispatchQueue.global(qos: .utility).async {
            let start = Date()
            do {
                _ = try self.models()
                FileLog.write(String(format: "PP-OCR load %.2fs", Date().timeIntervalSince(start)))
            } catch {
                FileLog.write("PP-OCR load failed: \(error)")
            }
        }
    }

    // MARK: Pipeline

    func recognize(_ image: CGImage) throws -> [RecognizedTextLine] {
        let (det, rec, characters) = try models()
        guard var source = RGBImage(image) else { throw PPOCRError.image }
        let originalWidth = source.width, originalHeight = source.height

        // Keep sides within 30...2000.
        let longSide = max(source.width, source.height), shortSide = min(source.width, source.height)
        if longSide > 2000 {
            source = source.resized(scale: 2000 / Double(longSide))
        } else if shortSide < 30 {
            source = source.resized(scale: 30 / Double(shortSide))
        }

        // Thin strips get black bands above and below so the detector sees
        // a sane aspect ratio.
        var padTop = 0
        if source.height <= 30 || Double(source.width) / Double(source.height) > 8 {
            let target = max(source.width / 8, 30) * 2
            padTop = abs(target - source.height) / 2
            source = source.paddedVertically(padTop)
        }

        let boxes = try detect(source, model: det)
        var fragments: [RecognizedTextLine] = []
        for box in boxes {
            guard let crop = source.cropped(box) else { continue }
            let line = crop.height * 2 >= crop.width * 3 ? crop.rotatedCounterClockwise() : crop
            guard let (text, score) = try recognizeLine(line, model: rec, characters: characters),
                  score >= 0.5 else { continue }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            // Back to the caller's image, Vision-normalized (bottom-left origin).
            let sx = Double(originalWidth) / Double(source.width)
            let sy = Double(originalHeight) / Double(source.height - padTop * 2)
            let x0 = Double(box.minX) * sx, x1 = Double(box.maxX) * sx
            let y0 = Double(box.minY - padTop) * sy, y1 = Double(box.maxY - padTop) * sy
            let rect = CGRect(
                x: max(0, x0) / Double(originalWidth),
                y: 1 - min(Double(originalHeight), y1) / Double(originalHeight),
                width: (min(Double(originalWidth), x1) - max(0, x0)) / Double(originalWidth),
                height: (min(Double(originalHeight), y1) - max(0, y0)) / Double(originalHeight)
            )
            fragments.append(RecognizedTextLine(text: trimmed, boundingBox: rect))
        }
        return OCRService.readingOrderLines(fragments, joinsCJK: true)
    }

    /// DB text detection: probability map → binarize at 0.3 → 2×2 dilation
    /// → connected regions scored ≥ 0.5 → expanded by the unclip ratio.
    private func detect(_ image: RGBImage, model: MLModel) throws -> [PixelBox] {
        var ratio = 1.0
        let shortSide = min(image.width, image.height)
        if shortSide < 736 { ratio = 736 / Double(shortSide) }
        // The converted detector accepts up to 4096 per side.
        ratio = min(ratio, 4096 / Double(max(image.width, image.height)))
        let h = max(32, Int((Double(image.height) * ratio / 32).rounded()) * 32)
        let w = max(32, Int((Double(image.width) * ratio / 32).rounded()) * 32)
        let resized = image.resized(width: w, height: h)

        let input = try resized.tensor(height: h, width: w, padWidth: w)
        let output = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["x": input]))
        guard let pred = output.featureValue(for: "y")?.multiArrayValue else { throw PPOCRError.output }
        let map = pred.floats(count: w * h)

        var bitmap = [Bool](repeating: false, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                // 2×2 dilation with the kernel anchored at its centre (cv2).
                var on = map[y * w + x] > 0.3
                if !on, x > 0 { on = map[y * w + x - 1] > 0.3 }
                if !on, y > 0 { on = map[(y - 1) * w + x] > 0.3 }
                if !on, x > 0, y > 0 { on = map[(y - 1) * w + x - 1] > 0.3 }
                bitmap[y * w + x] = on
            }
        }

        var visited = [Bool](repeating: false, count: w * h)
        var boxes: [PixelBox] = []
        var stack: [Int] = []
        for start in 0..<(w * h) where bitmap[start] && !visited[start] {
            var minX = w, minY = h, maxX = 0, maxY = 0
            var sum: Float = 0, count = 0
            visited[start] = true
            stack.append(start)
            while let p = stack.popLast() {
                let px = p % w, py = p / w
                sum += map[p]; count += 1
                minX = min(minX, px); maxX = max(maxX, px)
                minY = min(minY, py); maxY = max(maxY, py)
                for dy in -1...1 {
                    for dx in -1...1 {
                        let nx = px + dx, ny = py + dy
                        guard nx >= 0, ny >= 0, nx < w, ny < h else { continue }
                        let n = ny * w + nx
                        if bitmap[n] && !visited[n] { visited[n] = true; stack.append(n) }
                    }
                }
            }
            if boxes.count >= 1000 { break }
            let bw = Double(maxX - minX), bh = Double(maxY - minY)
            guard min(bw, bh) >= 3 else { continue }

            // Mean over the region's own pixels rather than its bounding box,
            // so a slightly tilted line is not diluted by the empty corners.
            guard sum / Float(count) >= 0.5 else { continue }

            let distance = bw * bh * 1.6 / (2 * (bw + bh))
            let ex0 = Double(minX) - distance, ex1 = Double(maxX) + distance
            let ey0 = Double(minY) - distance, ey1 = Double(maxY) + distance
            guard min(ex1 - ex0, ey1 - ey0) >= 5 else { continue }

            let sx = Double(image.width) / Double(w), sy = Double(image.height) / Double(h)
            let box = PixelBox(
                minX: Int((ex0 * sx).rounded()).clamped(0, image.width),
                minY: Int((ey0 * sy).rounded()).clamped(0, image.height),
                maxX: Int((ex1 * sx).rounded()).clamped(0, image.width),
                maxY: Int((ey1 * sy).rounded()).clamped(0, image.height)
            )
            guard box.maxX - box.minX > 3, box.maxY - box.minY > 3 else { continue }
            boxes.append(box)
        }
        return boxes
    }

    /// CTC recognition of one text line at height 48. Returns nil when the
    /// crop is degenerate.
    private func recognizeLine(_ line: RGBImage, model: MLModel, characters: [String]) throws -> (String, Float)? {
        guard line.width > 0, line.height > 0 else { return nil }
        let ratio = Double(line.width) / Double(line.height)
        let paddedWidth = min(4096, Int(48 * max(320.0 / 48, ratio)))
        let width = max(16, min(paddedWidth, Int(ceil(48 * ratio))))
        let resized = line.resized(width: width, height: 48)
        let input = try resized.tensor(height: 48, width: width, padWidth: paddedWidth)
        let output = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["x": input]))
        guard let probs = output.featureValue(for: "y")?.multiArrayValue, probs.shape.count == 3 else {
            throw PPOCRError.output
        }
        let steps = probs.shape[1].intValue, classes = probs.shape[2].intValue
        let values = probs.floats(count: steps * classes)
        var text = ""
        var confidences: [Float] = []
        var previous = -1
        for t in 0..<steps {
            var best = 0
            var bestValue = -Float.infinity
            let base = t * classes
            for c in 0..<classes where values[base + c] > bestValue {
                bestValue = values[base + c]
                best = c
            }
            defer { previous = best }
            guard best != 0, best != previous, best < characters.count else { continue }
            text += characters[best]
            confidences.append(bestValue)
        }
        guard !confidences.isEmpty else { return ("", 0) }
        return (text, confidences.reduce(0, +) / Float(confidences.count))
    }
}

enum PPOCRError: Error {
    case unavailable, image, output
}

struct PixelBox: Equatable {
    var minX, minY, maxX, maxY: Int
}

/// 8-bit RGB pixels, top row first.
struct RGBImage {
    let width: Int
    let height: Int
    var pixels: [UInt8] // RGBA

    init(width: Int, height: Int, pixels: [UInt8]) {
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// Draws onto opaque white, so transparent captures read as paper.
    init?(_ image: CGImage, width: Int? = nil, height: Int? = nil) {
        let w = width ?? image.width, h = height ?? image.height
        guard w > 0, h > 0 else { return nil }
        var buffer = [UInt8](repeating: 255, count: w * h * 4)
        let ok = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(
                data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            ctx.interpolationQuality = .high
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return nil }
        self.init(width: w, height: h, pixels: buffer)
    }

    func cgImage() -> CGImage? {
        let data = Data(pixels) as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
        )
    }

    func resized(scale: Double) -> RGBImage {
        resized(width: max(1, Int(Double(width) * scale)), height: max(1, Int(Double(height) * scale)))
    }

    func resized(width w: Int, height h: Int) -> RGBImage {
        guard w != width || h != height, let cg = cgImage(), let out = RGBImage(cg, width: w, height: h) else {
            return self
        }
        return out
    }

    func paddedVertically(_ pad: Int) -> RGBImage {
        guard pad > 0 else { return self }
        var black = [UInt8](repeating: 0, count: width * pad * 4)
        for i in stride(from: 3, to: black.count, by: 4) { black[i] = 255 }
        return RGBImage(width: width, height: height + pad * 2, pixels: black + pixels + black)
    }

    func cropped(_ box: PixelBox) -> RGBImage? {
        let w = box.maxX - box.minX, h = box.maxY - box.minY
        guard w > 0, h > 0 else { return nil }
        var out = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            let src = ((box.minY + y) * width + box.minX) * 4
            out.replaceSubrange((y * w * 4)..<((y + 1) * w * 4), with: pixels[src..<(src + w * 4)])
        }
        return RGBImage(width: w, height: h, pixels: out)
    }

    /// Same as numpy's rot90: the right edge becomes the top.
    func rotatedCounterClockwise() -> RGBImage {
        var out = [UInt8](repeating: 0, count: pixels.count)
        for y in 0..<height {
            for x in 0..<width {
                let src = (y * width + x) * 4
                let dst = ((width - 1 - x) * height + y) * 4
                out[dst..<(dst + 4)] = pixels[src..<(src + 4)]
            }
        }
        return RGBImage(width: height, height: width, pixels: out)
    }

    /// `1×3×H×W` Float32 in BGR order, scaled to -1...1, zero-padded on the
    /// right out to `padWidth`.
    func tensor(height h: Int, width w: Int, padWidth: Int) throws -> MLMultiArray {
        let array = try MLMultiArray(shape: [1, 3, NSNumber(value: h), NSNumber(value: padWidth)], dataType: .float32)
        let plane = h * padWidth
        let ptr = array.dataPointer.bindMemory(to: Float32.self, capacity: plane * 3)
        ptr.initialize(repeating: 0, count: plane * 3)
        for y in 0..<min(h, height) {
            for x in 0..<min(w, width) {
                let p = (y * width + x) * 4
                let o = y * padWidth + x
                ptr[o] = Float32(pixels[p + 2]) / 127.5 - 1
                ptr[plane + o] = Float32(pixels[p + 1]) / 127.5 - 1
                ptr[plane * 2 + o] = Float32(pixels[p]) / 127.5 - 1
            }
        }
        return array
    }
}

private extension MLMultiArray {
    /// Dense row-major Float32 copy. Core ML pads the last axis of its
    /// outputs, so rows are copied one at a time using the real strides;
    /// the subscript fallback costs about half a second per image.
    func floats(count: Int) -> [Float] {
        let dims = shape.map(\.intValue), steps = strides.map(\.intValue)
        guard let last = dims.last, last > 0, dims.reduce(1, *) == count else {
            return (0..<count).map { self[$0].floatValue }
        }
        let rows = count / last
        var out = [Float](repeating: 0, count: count)
        func rowOffset(_ row: Int) -> Int {
            var r = row, offset = 0
            for axis in stride(from: dims.count - 2, through: 0, by: -1) {
                offset += (r % dims[axis]) * steps[axis]
                r /= dims[axis]
            }
            return offset
        }
        let step = steps[dims.count - 1]
        out.withUnsafeMutableBufferPointer { dst in
            switch dataType {
            case .float32:
                let src = dataPointer.bindMemory(to: Float32.self, capacity: 1)
                for row in 0..<rows {
                    let base = rowOffset(row)
                    for i in 0..<last { dst[row * last + i] = src[base + i * step] }
                }
            #if arch(arm64)
            // Float16 does not exist on Intel Macs; there the generic path
            // below handles it.
            case .float16:
                let src = dataPointer.bindMemory(to: Float16.self, capacity: 1)
                for row in 0..<rows {
                    let base = rowOffset(row)
                    for i in 0..<last { dst[row * last + i] = Float(src[base + i * step]) }
                }
            #endif
            default:
                for i in 0..<count { dst[i] = self[i].floatValue }
            }
        }
        return out
    }
}

private extension Int {
    func clamped(_ lower: Int, _ upper: Int) -> Int { Swift.min(Swift.max(self, lower), upper) }
}
