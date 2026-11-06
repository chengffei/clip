import AppKit
import XCTest
@testable import Clip

/// Puts the capture toolbar on screen over a dimmed, colourful backdrop (as
/// it sits during a capture: outside the selection, under the 40 % black
/// scrim) and captures the screen region, so real Liquid Glass can be judged.
/// Runs only when `CLIP_SNAPSHOT_LIVE_DIR` is set; needs Screen Recording.
final class ToolbarGlassLiveTests: XCTestCase {
    func testToolbarGlassOverDimmedContent() throws {
        guard let dir = ProcessInfo.processInfo.environment["CLIP_SNAPSHOT_LIVE_DIR"] else { return }
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let screen = try XCTUnwrap(NSScreen.main)
        let size = NSSize(width: 900, height: 360)
        let origin = NSPoint(x: screen.frame.midX - size.width / 2, y: screen.frame.midY - size.height / 2)

        for (name, dim) in [("dim40", 0.40), ("dim62", 0.62), ("bright", 0.0)] {
            let backdrop = NSWindow(contentRect: NSRect(origin: origin, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
            backdrop.level = .floating
            backdrop.contentView = BackdropView(frame: NSRect(origin: .zero, size: size), dim: dim)
            backdrop.orderFrontRegardless()

            let layout = ToolbarLayout.default
            let bar = ToolbarView(items: layout.primary, overflow: layout.side)
            bar.updateSelection(tool: .rectangle)
            let panel = NSPanel(contentRect: NSRect(x: origin.x + (size.width - bar.frame.width) / 2, y: origin.y + 60,
                                                    width: bar.frame.width, height: bar.frame.height),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.level = .popUpMenu
            panel.appearance = NSAppearance(named: .aqua)
            panel.contentView = bar
            CaptureChrome.installGlassBackground(in: bar, cornerRadius: bar.plateCornerRadius)
            panel.orderFrontRegardless()
            RunLoop.main.run(until: Date().addingTimeInterval(1.0))

            let flippedY = screen.frame.maxY - (origin.y + size.height)
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            p.arguments = ["-x", "-R", "\(Int(origin.x)),\(Int(flippedY)),\(Int(size.width)),\(Int(size.height))",
                           URL(fileURLWithPath: dir).appendingPathComponent("live-\(name).png").path]
            try p.run()
            p.waitUntilExit()
            panel.orderOut(nil)
            backdrop.orderOut(nil)
        }
    }
}

private final class BackdropView: NSView {
    let dim: CGFloat
    init(frame: NSRect, dim: CGFloat) { self.dim = dim; super.init(frame: frame) }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        // A busy, colourful "screen": gradient, text-like bars, a photo-ish blob.
        NSGradient(colors: [.systemTeal, .systemIndigo, .systemPink, .systemOrange])?.draw(in: bounds, angle: 20)
        NSColor.white.withAlphaComponent(0.9).setFill()
        for i in 0..<9 {
            NSBezierPath(roundedRect: NSRect(x: 40, y: 30 + CGFloat(i) * 36, width: CGFloat(300 + (i * 97) % 480), height: 12), xRadius: 6, yRadius: 6).fill()
        }
        NSColor.black.withAlphaComponent(0.85).setFill()
        NSBezierPath(rect: NSRect(x: 520, y: 40, width: 300, height: 120)).fill()
        NSColor.black.withAlphaComponent(dim).setFill()
        bounds.fill(using: .sourceOver)
    }
}
