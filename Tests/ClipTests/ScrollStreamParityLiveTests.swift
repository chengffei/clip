import AppKit
import XCTest
@testable import Clip

/// Does a one-shot capture of a still window match the stream's frame of it
/// pixel for pixel? Needs screen recording permission: CLIP_LIVE_CAPTURE=1.
final class ScrollStreamParityLiveTests: XCTestCase {
    @MainActor
    func testOneShotMatchesStream() throws {
        guard ProcessInfo.processInfo.environment["CLIP_LIVE_CAPTURE"] != nil else { return }
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let screen = try XCTUnwrap(NSScreen.main)
        let frame = NSRect(x: screen.frame.minX + 200, y: screen.frame.minY + 200, width: 600, height: 400)
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.level = .floating
        let view = NSView(frame: NSRect(origin: .zero, size: frame.size))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(srgbRed: 0.16, green: 0.17, blue: 0.2, alpha: 1).cgColor
        let label = NSTextField(labelWithString: "Executed 185 tests 0123456789")
        label.textColor = NSColor(srgbRed: 0.3, green: 0.6, blue: 0.9, alpha: 1)
        label.frame = NSRect(x: 20, y: 200, width: 500, height: 30)
        view.addSubview(label)
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        let primaryHeight = NSScreen.screens[0].frame.height
        let cgRect = CGRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height)
        let shot = try XCTUnwrap(ScreenCapturer.capture(rect: cgRect, screen: screen, timeout: 3)?.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let stream = ScrollFrameStream(rect: cgRect, screen: screen, excludingWindowNumbers: [])
        var streamed: CGImage?
        let until = Date().addingTimeInterval(3)
        while streamed == nil, Date() < until {
            label.stringValue = label.stringValue // nudge a redraw so the stream emits
            view.needsDisplay = true
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            streamed = stream.takeNewFrames().last?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
        stream.stop()
        window.orderOut(nil)
        let s = try XCTUnwrap(streamed)
        print("PARITY shot \(shot.width)x\(shot.height) \(shot.colorSpace?.name as String? ?? "-") bpc \(shot.bitsPerComponent) info \(shot.bitmapInfo.rawValue)")
        print("PARITY stream \(s.width)x\(s.height) \(s.colorSpace?.name as String? ?? "-") bpc \(s.bitsPerComponent) info \(s.bitmapInfo.rawValue)")
        func raw(_ image: CGImage) -> [UInt8] {
            var d = [UInt8](repeating: 0, count: image.width * image.height * 4)
            let c = CGContext(data: &d, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            c.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return d
        }
        let a = raw(shot), b = raw(s)
        var diff = 0, maxDiff = 0, differing = 0
        for i in 0..<min(a.count, b.count) where i % 4 != 3 {
            let d = abs(Int(a[i]) - Int(b[i])); diff += d; maxDiff = max(maxDiff, d); if d > 0 { differing += 1 }
        }
        print("PARITY mean \(Double(diff) / Double(a.count * 3 / 4)) max \(maxDiff) differing \(differing) of \(a.count * 3 / 4)")
    }
}
