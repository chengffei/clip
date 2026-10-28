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
        let speeds: [CGFloat] = (ProcessInfo.processInfo.environment["CLIP_LIVE_SPEEDS"] ?? "1600,3200,4800,6400")
            .split(separator: ",").compactMap { Double($0) }.map { CGFloat($0) }
        var report: [String] = []
        for jumpy in [false, true] {
            for upward in [false, true] {
                for speed in speeds {
                    let (covered, expected) = try run(speed: speed, upward: upward, jumpy: jumpy)
                    report.append(String(format: "LIVE %@ %@ %4.0fpt/s covered %4.0f of %4.0fpt (%3.0f%%)",
                                         jumpy ? "jump  " : "smooth", upward ? "up  " : "down", speed, covered, expected, covered / expected * 100))
                }
            }
        }
        report.forEach { print($0) }
    }

    @MainActor
    private func run(speed: CGFloat, upward: Bool, jumpy: Bool) throws -> (covered: CGFloat, expected: CGFloat) {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let screen = try XCTUnwrap(NSScreen.main)
        let frame = NSRect(x: screen.frame.minX + 200, y: screen.frame.minY + 200, width: 600, height: 400)
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.level = .floating
        let scroll = NSScrollView(frame: NSRect(origin: .zero, size: frame.size))
        let text = LinesView(lineCount: 250)
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
        timer.schedule(deadline: .now() + 0.1, repeating: 0.05, leeway: .milliseconds(10))
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
            var travelled = min(distance, elapsed * speed)
            // Terminals jump whole wheel steps (3 lines) instead of gliding.
            if jumpy, travelled < distance { travelled = floor(travelled / 51) * 51 }
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
                .write(to: URL(fileURLWithPath: "\(dir)/live-speed-\(jumpy ? "jump" : "smooth")-\(upward ? "up" : "down")-\(Int(speed)).png"))
        }
        let sequence = try XCTUnwrap(LinesView.decodeLines(in: try XCTUnwrap(image.cgImagePreservingBacking())))
        var gaps = 0, repeats = 0
        var defects: [String] = []
        for (index, (a, b)) in zip(sequence, sequence.dropFirst()).enumerated() {
            if b == a { repeats += 1; defects.append("\(index):\(a)=\(b)") } else if b != a + 1 { gaps += 1; defects.append("\(index):\(a)->\(b)") }
        }
        print("LIVE lines \(sequence.first ?? -1)...\(sequence.last ?? -1) count \(sequence.count) gaps \(gaps) repeats \(repeats) \(defects.joined(separator: " "))")
        return (image.size.height - frame.height, distance)
    }
}

/// A terminal-like page whose every line carries its number twice: as text
/// and as a color block at the left edge, so a stitched capture can be read
/// back line by line.
private final class LinesView: NSView {
    static let lineHeight: CGFloat = 17
    private let lineCount: Int
    init(lineCount: Int) {
        self.lineCount = lineCount
        super.init(frame: NSRect(x: 0, y: 0, width: 600, height: CGFloat(lineCount) * Self.lineHeight))
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    /// Eight levels per channel, 32 apart, so color management on the way
    /// to the screen can't shift a block into its neighbour's code.
    static func color(for line: Int) -> NSColor {
        func level(_ v: Int) -> CGFloat { CGFloat(v * 32 + 16) / 255 }
        return NSColor(srgbRed: level(line % 8), green: level((line / 8) % 8), blue: level(4 + (line / 64) % 4), alpha: 1)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(srgbRed: 0.16, green: 0.17, blue: 0.2, alpha: 1).setFill()
        dirtyRect.fill()
        let words = ["swift test", "Executed 185 tests", "scroll capture frame", "overlap=233", "git push", "README.md", "Clip is running"]
        let first = max(0, Int(dirtyRect.minY / Self.lineHeight)), last = min(lineCount - 1, Int(dirtyRect.maxY / Self.lineHeight))
        guard first <= last else { return }
        for line in first...last {
            let y = CGFloat(line) * Self.lineHeight
            Self.color(for: line).setFill()
            NSRect(x: 0, y: y + 2, width: 14, height: Self.lineHeight - 4).fill()
            NSString(string: "\(words[line % words.count]) \(words[(line * 3) % words.count])").draw(
                at: NSPoint(x: 24, y: y + 1),
                withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                                 .foregroundColor: NSColor(white: 0.85, alpha: 1)])
        }
    }

    /// Line numbers read top to bottom from the left-edge blocks.
    static func decodeLines(in image: CGImage) -> [Int]? {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &data, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var lines: [Int] = []
        var inBlock = false
        let x = 14 // middle of the 14pt block at 2x
        for row in 0..<height {
            let i = (row * width + x) * 4
            let isBlock = data[i + 2] > 128
            if isBlock && !inBlock {
                func code(_ v: UInt8) -> Int { max(0, min(7, Int(v) / 32)) }
                lines.append(code(data[i]) + 8 * code(data[i + 1]) + 64 * (code(data[i + 2]) - 4))
            }
            inBlock = isBlock
        }
        return lines
    }
}
