import AppKit
import XCTest
@testable import Clip

/// Real ScreenCaptureKit run over an on-screen scrolling window. Needs screen
/// recording permission, so it only runs with CLIP_LIVE_CAPTURE=1.
final class ScrollCaptureLiveTests: XCTestCase {
    @MainActor
    func testScrollAndStitch() throws {
        guard ProcessInfo.processInfo.environment["CLIP_LIVE_CAPTURE"] != nil else { return }
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let screen = try XCTUnwrap(NSScreen.main)
        let frame = NSRect(x: screen.frame.minX + 200.3, y: screen.frame.minY + 200.6, width: 600, height: 400)
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.level = .floating
        let scroll = NSScrollView(frame: NSRect(origin: .zero, size: frame.size))
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        text.isVerticallyResizable = true
        text.font = .systemFont(ofSize: 14)
        text.string = (1...200).map { "第 \($0) 行：储能系统今日放电量 \($0 * 7) kWh，Long screenshot sharpness check." }.joined(separator: "\n")
        scroll.documentView = text
        scroll.hasVerticalScroller = false
        window.contentView = scroll
        window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))

        // CG global rect (top-left origin) of the window content.
        let primaryHeight = NSScreen.screens[0].frame.height
        let cgRect = CGRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height)
        let started = Date()
        var excluded: [CGWindowID] = []
        if ProcessInfo.processInfo.environment["CLIP_LIVE_EXCLUDE"] != nil {
            let hidden = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 50, height: 50), styleMask: [.borderless], backing: .buffered, defer: false)
            hidden.sharingType = .none
            excluded.append(CGWindowID(hidden.windowNumber))
            excluded.append(CGWindowID(window.windowNumber + 0))
            excluded.removeLast()
            print("LIVE excluding \(excluded)")
        }
        let capturer = ScrollCapturer(rect: cgRect, screen: screen, excludingWindowNumbers: excluded)
        print("LIVE init \(String(format: "%.2f", Date().timeIntervalSince(started)))s frames=\(capturer.frameCount)")
        for step in 1...6 {
            text.scroll(NSPoint(x: 0, y: CGFloat(step) * 150))
            RunLoop.main.run(until: Date().addingTimeInterval(0.15))
            let t = Date()
            let outcome = capturer.captureSynchronously(expectedShiftPoints: 0)
            print("LIVE step \(step) \(outcome) \(String(format: "%.2f", Date().timeIntervalSince(t)))s frames=\(capturer.frameCount)")
        }
        // The app's pattern: a background timer samples while the main
        // thread reads the frame count and shows toasts. This deadlocked on
        // 2026-10-27 when either side waited synchronously on the other.
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "test.manual-scroll", qos: .userInitiated))
        timer.schedule(deadline: .now(), repeating: 0.05)
        timer.setEventHandler { _ = capturer.captureSynchronously(expectedShiftPoints: 0) }
        timer.resume()
        let until = Date().addingTimeInterval(3)
        var reads = 0
        while Date() < until {
            _ = capturer.frameCount
            _ = ToastWindow.captureExcludedWindowNumbers
            reads += 1
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        timer.cancel()
        print("LIVE concurrent main reads=\(reads)")
        let done = expectation(description: "stitch")
        var result: NSImage?
        capturer.stopAndStitch { result = $0; done.fulfill() }
        wait(for: [done], timeout: 20)
        let image = try XCTUnwrap(result)
        let cg = try XCTUnwrap(image.cgImagePreservingBacking())
        print("LIVE stitched \(image.size) px \(cg.width)x\(cg.height)")
        if let dir = ProcessInfo.processInfo.environment["CLIP_SNAPSHOT_DIR"] {
            let rep = NSBitmapImageRep(cgImage: cg)
            try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/live-long.png"))
        }
        window.orderOut(nil)
    }
}

final class ScrollCaptureSharpnessLiveTests: XCTestCase {
    /// Same on-screen text captured through a fractional rect and through
    /// its pixel-aligned version; the aligned one should keep harder edges.
    @MainActor
    func testPixelAlignedCaptureIsSharper() throws {
        guard ProcessInfo.processInfo.environment["CLIP_LIVE_CAPTURE"] != nil else { return }
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.main)
        let frame = NSRect(x: screen.frame.minX + 300, y: screen.frame.minY + 300, width: 500, height: 200)
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.level = .floating
        let label = NSTextField(labelWithString: "Clip 清晰度 sharpness 0123456789 储能系统")
        label.font = .systemFont(ofSize: 15)
        label.frame = NSRect(x: 20, y: 80, width: 460, height: 30)
        window.contentView?.addSubview(label)
        window.backgroundColor = .white
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        let primaryHeight = NSScreen.screens[0].frame.height
        let fractional = CGRect(x: frame.minX + 10.3, y: primaryHeight - frame.maxY + 10.3, width: 480.4, height: 180.2)
        let aligned = ScrollCapturer.pixelAligned(fractional, scale: screen.backingScaleFactor)
        func sharpness(_ rect: CGRect) throws -> Double {
            let image = try XCTUnwrap(ScreenCapturer.capture(rect: rect, screen: screen, timeout: 3))
            let cg = try XCTUnwrap(image.cgImagePreservingBacking())
            let w = cg.width, h = cg.height
            var gray = [UInt8](repeating: 0, count: w * h)
            let ctx = CGContext(data: &gray, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0)!
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            var steps: [Int] = []
            for y in 0..<h { for x in 1..<w { steps.append(abs(Int(gray[y * w + x]) - Int(gray[y * w + x - 1]))) } }
            steps.sort()
            return Double(steps[Int(Double(steps.count) * 0.998)])
        }
        let soft = try sharpness(fractional), crisp = try sharpness(aligned)
        print("LIVE sharpness fractional=\(soft) aligned=\(crisp)")
        // Content scrolled to a fractional offset.
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 500, height: 200))
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 2000))
        text.font = .systemFont(ofSize: 15)
        text.string = (1...80).map { "第 \($0) 行 Clip 清晰度 sharpness 储能系统" }.joined(separator: "\n")
        scroll.documentView = text
        window.contentView = scroll
        for offset in [100.0, 100.25, 100.5, 100.75] {
            scroll.contentView.scroll(to: NSPoint(x: 0, y: offset))
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))
            print("LIVE scrolled offset=\(offset) sharpness=\(try sharpness(aligned))")
        }
        window.orderOut(nil)
        XCTAssertGreaterThanOrEqual(crisp, soft)
    }
}
