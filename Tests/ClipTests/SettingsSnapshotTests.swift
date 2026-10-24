import AppKit
import XCTest
@testable import Clip

/// Renders the settings view offscreen so its look can be checked without
/// screen-recording permission. Writes PNGs only when `CLIP_SNAPSHOT_DIR`
/// is set; otherwise just asserts the view lays out.
final class SettingsSnapshotTests: XCTestCase {
    func testSettingsViewRenders() throws {
        _ = NSApplication.shared
        let view = SettingsView(frame: NSRect(x: 0, y: 0, width: 820, height: 600), isStartup: false)
        view.appearance = NSAppearance(named: .aqua)
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.backgroundColor = Brand.sidebar
        window.contentView = view
        view.setStartupMode(false)
        view.layoutSubtreeIfNeeded()

        guard let dir = ProcessInfo.processInfo.environment["CLIP_SNAPSHOT_DIR"] else { return }
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        let data = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("settings.png"))
    }
}
