import AppKit
import XCTest
@testable import Clip

/// Real ScreenCaptureKit run while an on-screen terminal-like window scrolls
/// continuously, sampled the way the app does (every 80ms). Checks how much
/// of the scrolled distance ends up in the stitched image at several speeds,
/// both directions. Needs screen recording permission: CLIP_LIVE_CAPTURE=1.
final class ScrollCaptureSpeedLiveTests: XCTestCase {
    @MainActor
    func testContinuousScrollAtSpeeds() throws {
        guard ProcessInfo.processInfo.environment["CLIP_LIVE_CAPTURE"] != nil else { return }
        let speeds: [CGFloat] = (ProcessInfo.processInfo.environment["CLIP_LIVE_SPEEDS"] ?? "800,1600,3200")
            .split(separator: ",").compactMap { Double($0) }.map { CGFloat($0) }
        var report: [String] = []
        for upward in [false, true] {
            for speed in speeds {
                let (covered, expected) = try run(speed: speed, upward: upward)
                report.append(String(format: "LIVE %@ %4.0fpt/s covered %4.0f of %4.0fpt (%3.0f%%)",
                                     upward ? "up  " : "down", speed, covered, expected, covered / expected * 100))
            }
        }
        report.forEach { print($0) }
    }

    @MainActor
    private func run(speed: CGFloat, upward: Bool) throws -> (covered: CGFloat, expected: CGFloat) {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let screen = try XCTUnwrap(NSScreen.main)
        let frame = NSRect(x: screen.frame.minX + 200, y: screen.frame.minY + 200, width: 600, height: 400)
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.level = .floating
        let scroll = NSScrollView(frame: NSRect(origin: .zero, size: frame.size))
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        text.isVerticallyResizable = true
        text.backgroundColor = NSColor(srgbRed: 0.16, green: 0.17, blue: 0.2, alpha: 1)
        text.textColor = NSColor(white: 0.85, alpha: 1)
        text.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        let words = ["swift test", "Executed 185 tests", "scroll capture frame", "overlap=233", "git push", "README.md", "Clip is running"]
        text.string = (1...400).map { "\($0)  \(words[$0 % words.count]) \(words[($0 * 3) % words.count])" }.joined(separator: "\n")
        scroll.documentView = text
        scroll.hasVerticalScroller = false
        window.contentView = scroll
        window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        let maxOffset = text.frame.height - frame.height
        let startOffset: CGFloat = upward ? maxOffset - 40 : 40
        text.scroll(NSPoint(x: 0, y: startOffset))
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))

        let primaryHeight = NSScreen.screens[0].frame.height
        let cgRect = CGRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height)
        let capturer = ScrollCapturer(rect: cgRect, screen: screen, excludingWindowNumbers: [])
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "test.speed", qos: .userInitiated))
        timer.schedule(deadline: .now() + 0.1, repeating: 0.08, leeway: .milliseconds(20))
        timer.setEventHandler { _ = capturer.captureSynchronously(expectedShiftPoints: 0) }
        timer.resume()
        // People start scrolling a moment after clicking the button.
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))

        // Scroll 1600pt at the given speed, one step per display frame.
        let distance: CGFloat = 1600
        let started = Date()
        var offset = startOffset
        while abs(offset - startOffset) < distance {
            let elapsed = CGFloat(Date().timeIntervalSince(started))
            let travelled = min(distance, elapsed * speed)
            offset = upward ? startOffset - travelled : startOffset + travelled
            text.scroll(NSPoint(x: 0, y: offset))
            RunLoop.main.run(until: Date().addingTimeInterval(1.0 / 60))
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        timer.cancel()

        let done = expectation(description: "stitch")
        var result: NSImage?
        capturer.stopAndStitch { result = $0; done.fulfill() }
        wait(for: [done], timeout: 30)
        window.orderOut(nil)
        let image = try XCTUnwrap(result)
        if let dir = ProcessInfo.processInfo.environment["CLIP_SNAPSHOT_DIR"],
           let cg = image.cgImagePreservingBacking() {
            try NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?
                .write(to: URL(fileURLWithPath: "\(dir)/live-speed-\(upward ? "up" : "down")-\(Int(speed)).png"))
        }
        return (image.size.height - frame.height, distance)
    }
}
