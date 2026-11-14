import AppKit
import XCTest
@testable import Clip

/// Renders the recording HUD and a pinned image with its hover toolbar
/// offscreen over a busy backdrop. Writes PNGs only when `CLIP_SNAPSHOT_DIR`
/// is set (optional `CLIP_SNAPSHOT_PREFIX`, e.g. `before-`); otherwise it just
/// checks the views lay out. Window-server effects (window shadow, live glass
/// refraction) are not part of `cacheDisplay` output.
@MainActor
final class HUDPinSnapshotTests: XCTestCase {
    func testRecordingHUDRenders() throws {
        _ = NSApplication.shared
        for paused in [false, true] {
            let hud = RecordingHUDPanel()
            hud.update(elapsedSeconds: 83)
            if paused { hud.setPaused(true) }
            let content = try XCTUnwrap(hud.contentView)
            let size = hud.frame.size
            XCTAssertEqual(size.height, FloatingControlChrome.height)

            hud.contentView = NSView()
            let host = Self.makeHost(size: NSSize(width: size.width + 48, height: size.height + 40))
            content.frame = NSRect(origin: NSPoint(x: 24, y: 20), size: size)
            host.addSubview(content)
            try Self.write(host, name: paused ? "hud-paused" : "hud")
        }
    }

    func testRecordingBorderRenders() throws {
        _ = NSApplication.shared
        guard let screen = NSScreen.main else { return }
        let panel = RecordingBorderPanel(screen: screen)
        panel.setSelectionRect(NSRect(
            x: screen.frame.minX + 30,
            y: screen.frame.minY + 30,
            width: 200,
            height: 120
        ))
        let border = try XCTUnwrap(panel.contentView)
        panel.contentView = NSView()
        let host = Self.makeHost(size: NSSize(width: 260, height: 180))
        border.frame = NSRect(origin: .zero, size: screen.frame.size)
        host.addSubview(border)
        try Self.write(host, name: "recording-border")
    }

    func testPinWithToolbarRenders() throws {
        _ = NSApplication.shared
        let imageSize = NSSize(width: 360, height: 220)
        let image = Self.makeScreenshotLikeImage(size: imageSize)
        let host = Self.makeHost(size: NSSize(width: imageSize.width + 80, height: imageSize.height + 80))

        let pin = PinContentView(frame: NSRect(origin: NSPoint(x: 40, y: 40), size: imageSize))
        pin.image = image
        host.addSubview(pin)

        // The real toolbar only appears on hover; place one where it would be.
        let toolbar = PinToolbarView()
        toolbar.frame = PinImageLayout.toolbarFrame(
            in: pin.frame,
            preferredSize: NSSize(width: PinToolbarView.preferredWidth, height: PinToolbarView.preferredHeight)
        )
        toolbar.zoomScale = 1.25
        host.addSubview(toolbar)
        host.layoutSubtreeIfNeeded()
        try Self.write(host, name: "pin")

        toolbar.isOCRActive = true
        host.layoutSubtreeIfNeeded()
        try Self.write(host, name: "pin-ocr-active")
    }

    func testRecordingHUDContextMenuMirrorsControls() {
        _ = NSApplication.shared
        let hud = RecordingHUDPanel()
        let menu = hud.makeContextMenu()
        let titles = menu.items.filter { !$0.isSeparatorItem }.map(\.title)
        XCTAssertEqual(titles, [
            L10n.recordingPause,
            L10n.recordingStop,
        ])
        XCTAssertTrue(menu.items.allSatisfy { $0.keyEquivalent.isEmpty }, "context menus don't show shortcuts")

        hud.setPaused(true)
        XCTAssertEqual(hud.makeContextMenu().items.first?.title, L10n.recordingResume)
    }

    func testPinContextMenuOffersToolbarCommands() throws {
        _ = NSApplication.shared
        let pin = PinContentView(frame: NSRect(x: 0, y: 0, width: 200, height: 120))
        pin.image = Self.makeScreenshotLikeImage(size: NSSize(width: 200, height: 120))
        let event = try XCTUnwrap(NSEvent.mouseEvent(
            with: .rightMouseDown, location: NSPoint(x: 50, y: 50), modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ))
        let menu = try XCTUnwrap(pin.menu(for: event))
        let titles = menu.items.filter { !$0.isSeparatorItem }.map(\.title)
        XCTAssertEqual(titles, [L10n.pinMenuCopy, L10n.pinMenuEdit, L10n.pinMenuRecognizeText, L10n.pinMenuClose])
        XCTAssertTrue(menu.items.allSatisfy { $0.keyEquivalent.isEmpty })
        XCTAssertTrue(pin.responds(to: #selector(NSText.copy(_:))), "Edit > Copy (⌘C) reaches the pin")
    }

    // MARK: - Helpers

    private static func makeHost(size: NSSize) -> NSView {
        let host = BackdropView(frame: NSRect(origin: .zero, size: size))
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        return host
    }

    private static func write(_ host: NSView, name: String) throws {
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        guard let dir = ProcessInfo.processInfo.environment["CLIP_SNAPSHOT_DIR"] else { return }
        let prefix = ProcessInfo.processInfo.environment["CLIP_SNAPSHOT_PREFIX"] ?? ""
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let data = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(prefix)\(name).png"))
    }

    /// A light, document-like screenshot: white page, grey text bars, a photo block.
    private static func makeScreenshotLikeImage(size: NSSize) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            NSColor.white.setFill()
            rect.fill()
            NSColor(white: 0.93, alpha: 1).setFill()
            NSRect(x: 0, y: rect.maxY - 28, width: rect.width, height: 28).fill()
            NSColor(white: 0.78, alpha: 1).setFill()
            for row in 0..<7 {
                let width = rect.width * (row % 3 == 2 ? 0.45 : 0.62)
                NSBezierPath(roundedRect: NSRect(x: 16, y: rect.maxY - 56 - CGFloat(row) * 20, width: width, height: 8), xRadius: 4, yRadius: 4).fill()
            }
            NSGradient(colors: [NSColor.systemTeal, NSColor.systemIndigo])?
                .draw(in: NSRect(x: rect.maxX - 130, y: 18, width: 114, height: 120), angle: 60)
            return true
        }
    }
}

/// Busy desktop-like backdrop so translucent chrome shows what it sits on.
private final class BackdropView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSGradient(colors: [
            NSColor(srgbRed: 0.98, green: 0.62, blue: 0.42, alpha: 1),
            NSColor(srgbRed: 0.45, green: 0.62, blue: 0.95, alpha: 1),
        ])?.draw(in: bounds, angle: 25)
        NSColor.white.withAlphaComponent(0.35).setFill()
        var x: CGFloat = -40
        while x < bounds.maxX {
            NSRect(x: x, y: 0, width: 14, height: bounds.height).fill()
            x += 46
        }
    }
}
