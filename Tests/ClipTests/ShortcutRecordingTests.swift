import AppKit
import Carbon.HIToolbox
import XCTest
@testable import Clip

final class ShortcutRecordingTests: XCTestCase {
    private func key(_ code: Int, _ chars: String, _ flags: NSEvent.ModifierFlags, window: NSWindow) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                         windowNumber: window.windowNumber, context: nil, characters: chars,
                         charactersIgnoringModifiers: chars, isARepeat: false, keyCode: UInt16(code))!
    }

    private func record(_ flags: NSEvent.ModifierFlags) -> (Int, Int) {
        let hadCustom = Defaults.hasCustomScreenshotHotkey
        let oldCode = Defaults.screenshotHotkeyKeyCode, oldMods = Defaults.screenshotHotkeyModifiers
        defer {
            if hadCustom { Defaults.screenshotHotkeyKeyCode = oldCode; Defaults.screenshotHotkeyModifiers = oldMods } else { Defaults.clearScreenshotHotkey() }
            HotkeyManager.shared.endRecording()
        }
        Defaults.screenshotHotkeyKeyCode = kVK_F19; Defaults.screenshotHotkeyModifiers = 0
        let view = SettingsView(frame: NSRect(x: 0, y: 0, width: 680, height: 600), isStartup: false)
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        window.orderFrontRegardless()
        window.makeKey()
        view.perform(NSSelectorFromString("shortcutSetClicked"))
        NSApp.sendEvent(key(kVK_ANSI_K, "k", flags, window: window))
        let result = (Defaults.screenshotHotkeyKeyCode, Defaults.screenshotHotkeyModifiers)
        window.orderOut(nil)
        return result
    }

    func testRecordsCommandLetter() {
        let (code, mods) = record([.command, .shift])
        XCTAssertEqual(code, kVK_ANSI_K)
        XCTAssertEqual(mods, cmdKey | shiftKey)
    }

    func testRecordsCommandOnlyLetter() {
        let (code, mods) = record([.command])
        XCTAssertEqual(code, kVK_ANSI_K)
        XCTAssertEqual(mods, cmdKey)
    }

    func testRecordsControlLetter() {
        let (code, mods) = record([.control, .shift])
        XCTAssertEqual(code, kVK_ANSI_K)
        XCTAssertEqual(mods, controlKey | shiftKey)
    }

    private func flags(_ f: CGEventFlags, at t: TimeInterval, window: NSWindow) -> NSEvent {
        let cg = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Command), keyDown: true)!
        cg.type = .flagsChanged
        cg.flags = f
        cg.timestamp = CGEventTimestamp(t * 1_000_000_000)
        return NSEvent(cgEvent: cg)!
    }

    func testDoubleCommandRestoresDefaultTrigger() {
        let hadCustom = Defaults.hasCustomScreenshotHotkey
        let oldCode = Defaults.screenshotHotkeyKeyCode, oldMods = Defaults.screenshotHotkeyModifiers
        defer {
            if hadCustom { Defaults.screenshotHotkeyKeyCode = oldCode; Defaults.screenshotHotkeyModifiers = oldMods } else { Defaults.clearScreenshotHotkey() }
            HotkeyManager.shared.endRecording()
        }
        Defaults.screenshotHotkeyKeyCode = kVK_ANSI_K
        Defaults.screenshotHotkeyModifiers = cmdKey | shiftKey
        XCTAssertTrue(Defaults.hasCustomScreenshotHotkey)
        let view = SettingsView(frame: NSRect(x: 0, y: 0, width: 680, height: 600), isStartup: false)
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        window.orderFrontRegardless()
        window.makeKey()
        view.perform(NSSelectorFromString("shortcutSetClicked"))
        let t = ProcessInfo.processInfo.systemUptime
        NSApp.sendEvent(flags(.maskCommand, at: t, window: window))
        NSApp.sendEvent(flags([], at: t + 0.05, window: window))
        NSApp.sendEvent(flags(.maskCommand, at: t + 0.15, window: window))
        NSApp.sendEvent(flags([], at: t + 0.2, window: window))
        XCTAssertFalse(Defaults.hasCustomScreenshotHotkey)
        XCTAssertFalse(HotkeyManager.shared.isRecording)
        window.orderOut(nil)
    }

    func testDetectorIgnoresSlowOrInterruptedTaps() {
        func ev(_ f: NSEvent.ModifierFlags, _ t: TimeInterval) -> NSEvent {
            let cg = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Command), keyDown: true)!
            cg.type = .flagsChanged
            var c: CGEventFlags = []
            if f.contains(.command) { c.insert(.maskCommand) }
            if f.contains(.shift) { c.insert(.maskShift) }
            cg.flags = c
            cg.timestamp = CGEventTimestamp(t * 1_000_000_000)
            return NSEvent(cgEvent: cg)!
        }
        var d = DoubleCommandTapDetector()
        XCTAssertFalse(d.handle(ev(.command, 1.0), interval: 0.3))
        XCTAssertFalse(d.handle(ev([], 1.05), interval: 0.3))
        XCTAssertFalse(d.handle(ev(.command, 1.5), interval: 0.3), "too slow")
        XCTAssertFalse(d.handle(ev([.command, .shift], 1.55), interval: 0.3))
        XCTAssertFalse(d.handle(ev([], 1.6), interval: 0.3))
        XCTAssertFalse(d.handle(ev(.command, 1.65), interval: 0.3), "shift interrupted")
        XCTAssertFalse(d.handle(ev([], 1.7), interval: 0.3))
        XCTAssertTrue(d.handle(ev(.command, 1.8), interval: 0.3))
    }
}
