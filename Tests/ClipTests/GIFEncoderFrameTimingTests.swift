import CoreVideo
import ImageIO
import UniformTypeIdentifiers
import XCTest

@testable import capcap

/// GIF export must preserve the original clip duration when the source frame
/// rate is not a clean multiple of the GIF target rate. The encoder drops
/// source frames with an integer `sourceEstimatedFPS / targetFPS` ratio and
/// then stamps every retained frame with a per-frame delay. That delay must
/// describe the real span each retained frame represents
/// (`keepEvery / sourceEstimatedFPS`), not a fixed `1 / targetFPS`, otherwise
/// a 24fps clip exported to 15fps plays back in slow motion.
final class GIFEncoderFrameTimingTests: XCTestCase {
    /// Small solid-color BGRA pixel buffer suitable for feeding the encoder.
    private func makePixelBuffer(width: Int = 4, height: Int = 4) -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )
        XCTAssertEqual(status, kCVReturnSuccess, "CVPixelBufferCreate failed")
        guard let buffer = pixelBuffer else { fatalError("pixelBuffer was nil") }

        CVPixelBufferLockBaseAddress(buffer, .init(rawValue: 0))
        let baseAddress = CVPixelBufferGetBaseAddress(buffer)
        let dataSize = CVPixelBufferGetDataSize(buffer)
        if let baseAddress { memset(baseAddress, 0xFF, dataSize) }
        CVPixelBufferUnlockBaseAddress(buffer, .init(rawValue: 0))
        return buffer
    }

    /// Encodes `frames` frames at `sourceFPS` into a `targetFPS` GIF and returns
    /// the total playback duration (seconds), summed from the per-frame delay
    /// ImageIO writes into the finalized file.
    @discardableResult
    private func totalDuration(targetFPS: Int, sourceFPS: Int, frames: Int) -> Double {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("capcap-gif-timing-\(UUID().uuidString).gif")
        defer { try? FileManager.default.removeItem(at: url) }

        let encoder = GIFEncoder(url: url, fps: targetFPS, sourceFPS: sourceFPS)
        for _ in 0..<frames {
            encoder.addFrame(makePixelBuffer())
        }
        XCTAssertTrue(encoder.finish(), "GIFEncoder failed to finalize the GIF")

        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            XCTFail("Could not open the written GIF at \(url)")
            return 0
        }

        var total: Double = 0
        let frameCount = CGImageSourceGetCount(imageSource)
        for index in 0..<frameCount {
            guard
                let cfProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, index, nil) as? [CFString: Any],
                let gifDictionary = cfProperties[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            else { continue }
            // ImageIO reads these keys back as the kCGImagePropertyGIF...
            // CFString constants (their on-disk form, e.g. "{GIF}"), so index
            // with the constants rather than bare Strings. Prefer the clamped
            // DelayTime; fall back to UnclampedDelayTime if it is absent.
            let delay = (gifDictionary[kCGImagePropertyGIFDelayTime] as? Double)
                ?? (gifDictionary[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
                ?? 0
            total += delay
        }
        return total
    }

    /// 24fps source exported to a 15fps GIF: sourceFPS sits between target and
    /// 2*target, so every source frame is retained. The clip must still last
    /// ~1.0s. Before the fix each retained frame carried a 1/targetFPS delay,
    /// stretching 24 frames to ~1.6s (slow motion).
    func testNonMultipleSourceFrameRatePlaysInRealTime() {
        let total = totalDuration(targetFPS: 15, sourceFPS: 24, frames: 24)
        XCTAssertEqual(total, 1.0, accuracy: 0.1)
    }

    /// 30fps -> 15fps divides cleanly (keepEvery = 2). It already plays in real
    /// time and must continue to do so after the fix — a regression guard that
    /// is green both before and after the change.
    func testMultipleSourceFrameRateStaysInRealTime() {
        let total = totalDuration(targetFPS: 15, sourceFPS: 30, frames: 30)
        XCTAssertEqual(total, 1.0, accuracy: 0.1)
    }
}
