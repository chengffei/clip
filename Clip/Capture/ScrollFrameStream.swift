import AppKit
import ScreenCaptureKit

/// A live ScreenCaptureKit stream of the long-screenshot rect. One-shot
/// screenshots re-enumerate every window and took 100–250ms each, so fast
/// scrolls outran the polls and frames stopped overlapping (2026-10-28).
/// The stream keeps the newest frame ready; polls just take it.
final class ScrollFrameStream: NSObject, SCStreamOutput {
    private let lock = NSLock()
    private var latest: NSImage?
    private var latestSerial = 0
    private var takenSerial = 0
    private var takenCount = 0
    private var stream: SCStream?
    private let queue = DispatchQueue(label: "clip.scroll-stream", qos: .userInitiated)
    private let pointSize: NSSize

    init(rect: CGRect, screen: NSScreen, excludingWindowNumbers: [CGWindowID]) {
        pointSize = rect.size
        super.init()
        let scale = max(screen.backingScaleFactor, 1)
        let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        Task { [weak self] in
            do {
                let content = try await SCShareableContent.current
                guard let self,
                      let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first
                else { return }
                let excluded = content.windows.filter { excludingWindowNumbers.contains($0.windowID) }
                let filter = SCContentFilter(display: display, excludingWindows: excluded)
                let bounds = CGDisplayBounds(display.displayID)
                let config = SCStreamConfiguration()
                config.sourceRect = CGRect(x: rect.minX - bounds.minX, y: rect.minY - bounds.minY,
                                           width: rect.width, height: rect.height)
                config.width = max(Int(ceil(rect.width * scale)), 1)
                config.height = max(Int(ceil(rect.height * scale)), 1)
                config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
                config.queueDepth = 3
                config.showsCursor = false
                config.capturesAudio = false
                config.pixelFormat = kCVPixelFormatType_32BGRA
                let stream = SCStream(filter: filter, configuration: config, delegate: nil)
                try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: self.queue)
                try await stream.startCapture()
                self.lock.withLock { self.stream = stream }
            } catch {
                FileLog.write("scroll stream failed: \(error.localizedDescription)")
            }
        }
    }

    /// The newest frame not handed out yet, or nil when nothing new arrived.
    func takeNewFrame() -> NSImage? {
        lock.withLock {
            guard latestSerial != takenSerial else { return nil }
            takenSerial = latestSerial
            takenCount += 1
            return latest
        }
    }

    var isRunning: Bool { lock.withLock { stream != nil } }

    func stop() {
        lock.withLock { FileLog.write("scroll stream frames=\(latestSerial) taken=\(takenCount)") }
        let stream = lock.withLock { () -> SCStream? in
            defer { self.stream = nil }
            return self.stream
        }
        stream?.stopCapture { _ in }
    }

    private static func copyImage(from pixelBuffer: CVPixelBuffer) -> CGImage? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let width = CVPixelBufferGetWidth(pixelBuffer), height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let data = Data(bytes: base, count: bytesPerRow * height)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        let colorSpace = CVImageBufferGetColorSpace(pixelBuffer)?.takeUnretainedValue()
            ?? CGColorSpace(name: CGColorSpace.sRGB)!
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let statusRaw = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: statusRaw) == .complete,
              let pixelBuffer = sampleBuffer.imageBuffer
        else { return }
        // Copy the pixels out: holding the stream's own buffers starves its
        // small pool and the stream stops delivering. No color conversion,
        // so stream frames match one-shot captures.
        guard let cgImage = Self.copyImage(from: pixelBuffer) else { return }
        let image = NSImage(cgImage: cgImage, size: pointSize)
        lock.withLock {
            latest = image
            latestSerial += 1
        }
    }
}
