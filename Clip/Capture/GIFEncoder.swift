import CoreGraphics
import CoreVideo
import Foundation
import ImageIO
import UniformTypeIdentifiers

final class GIFEncoder {
    private let url: URL
    private let targetFPS: Int
    private let sourceEstimatedFPS: Int
    private let keepEvery: Int
    private let frameProperties: [CFString: Any]
    private let gifProperties: [CFString: Any]
    private var destination: CGImageDestination?
    private var inputFrameCount = 0
    private var frameCount = 0
    private let lock = NSLock()
    /// Longest side of an exported GIF frame, in pixels.
    static let maxLongEdge = 1600

    init(url: URL, fps: Int, sourceFPS: Int) {
        self.url = url
        self.targetFPS = min(max(fps, 1), 15)
        self.sourceEstimatedFPS = max(sourceFPS, self.targetFPS)
        self.keepEvery = max(1, self.sourceEstimatedFPS / self.targetFPS)

        // Each retained frame represents `keepEvery` source frames, so its delay
        // is the span those frames cover (`keepEvery / sourceEstimatedFPS`),
        // not a flat `1 / targetFPS`. The flat value only holds when the source
        // rate is a clean multiple of the target; otherwise the GIF plays in slow
        // motion because every retained frame is stretched to 1/targetFPS.
        let delayTime = Float(self.keepEvery) / Float(self.sourceEstimatedFPS)
        frameProperties = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: delayTime,
                kCGImagePropertyGIFLoopCount: 0,
            ] as [CFString: Any]
        ]
        gifProperties = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFLoopCount: 0,
            ] as [CFString: Any]
        ]

        destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.gif.identifier as CFString,
            Int.max,
            nil
        )
        if let destination {
            CGImageDestinationSetProperties(destination, gifProperties as CFDictionary)
        }
    }

    func addFrame(_ pixelBuffer: CVPixelBuffer) {
        lock.lock()
        defer { lock.unlock() }

        inputFrameCount += 1
        guard (inputFrameCount - 1) % keepEvery == 0 else { return }
        guard let destination else { return }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
        else { return }

        let bitmapInfo = CGImageAlphaInfo.noneSkipFirst.rawValue
            | CGBitmapInfo.byteOrder32Little.rawValue
        guard let sourceContext = CGContext(
            data: baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ), let sourceImage = sourceContext.makeImage() else {
            return
        }

        // ImageIO keeps every GIF frame in memory until finalize, so a long
        // Retina recording at native pixels ran into gigabytes. Cap the long
        // edge; GIFs are a preview format and do not need 2× pixels.
        let longEdge = max(width, height)
        let outputScale = longEdge > Self.maxLongEdge ? CGFloat(Self.maxLongEdge) / CGFloat(longEdge) : 1
        let outputWidth = max(1, Int((CGFloat(width) * outputScale).rounded()))
        let outputHeight = max(1, Int((CGFloat(height) * outputScale).rounded()))
        guard let ownedContext = CGContext(
            data: nil,
            width: outputWidth,
            height: outputHeight,
            bitsPerComponent: 8,
            bytesPerRow: outputWidth * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return }
        ownedContext.interpolationQuality = .high
        ownedContext.draw(sourceImage, in: CGRect(x: 0, y: 0, width: outputWidth, height: outputHeight))
        guard let ownedImage = ownedContext.makeImage() else { return }

        CGImageDestinationAddImage(destination, ownedImage, frameProperties as CFDictionary)
        frameCount += 1
    }

    func finish() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard let destination, frameCount > 0 else { return false }
        let ok = CGImageDestinationFinalize(destination)
        self.destination = nil
        return ok
    }
}
