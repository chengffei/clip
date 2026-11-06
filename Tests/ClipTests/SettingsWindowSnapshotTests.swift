import AppKit
import XCTest
@testable import Clip

/// Shows the real settings window (toolbar, title, fitted height) on screen
/// and captures each pane with `screencapture -l`. Runs only when
/// `CLIP_SNAPSHOT_WINDOW_DIR` is set, since it puts a window on screen and
/// needs Screen Recording for the test runner.
final class SettingsWindowSnapshotTests: XCTestCase {
    func testSettingsWindowPanes() throws {
        guard let dir = ProcessInfo.processInfo.environment["CLIP_SNAPSHOT_WINDOW_DIR"] else { return }
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        if let lang = ProcessInfo.processInfo.environment["CLIP_SNAPSHOT_LANG"], let language = AppLanguage(rawValue: lang) {
            Defaults.language = language
        }
        let controller = SettingsWindowController.shared
        controller.showAsSettings(focusingPermissions: false)
        let window = try XCTUnwrap(controller.window)
        for tab in SettingsTab.allCases {
            if let item = window.toolbar?.items.first(where: { $0.itemIdentifier.rawValue == tab.rawValue }) {
                NSApp.sendAction(item.action!, to: item.target, from: item)
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.6))
            let out = URL(fileURLWithPath: dir).appendingPathComponent("window-\(tab.rawValue).png").path
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            p.arguments = ["-x", "-o", "-l", "\(window.windowNumber)", out]
            try p.run()
            p.waitUntilExit()
        }
        window.orderOut(nil)
    }
}
