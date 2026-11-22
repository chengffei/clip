import AppKit
import XCTest
@testable import Clip

final class RecordingClipboardTests: XCTestCase {
    func testRecordingFileGoesOnTheClipboardAsAFile() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("clip.test.recording"))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("clip-test.gif")
        try Data("GIF89a".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertTrue(ClipboardManager.copyRecordingFile(url, pasteboard: pasteboard))
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        XCTAssertEqual(urls?.first?.standardizedFileURL, url.standardizedFileURL)
        XCTAssertNotNil(pasteboard.data(forType: NSPasteboard.PasteboardType("com.compuserve.gif")))
    }

    func testUnsetRecordingPreferenceFollowsLastFormatInsteadOfAsking() {
        let defaults = UserDefaults.standard
        let savedPreference = defaults.object(forKey: "recordingSavePreference")
        let savedFormat = defaults.object(forKey: "recordingSaveFormat")
        defer {
            defaults.set(savedPreference, forKey: "recordingSavePreference")
            defaults.set(savedFormat, forKey: "recordingSaveFormat")
        }
        defaults.removeObject(forKey: "recordingSavePreference")
        defaults.set("gif", forKey: "recordingSaveFormat")
        XCTAssertEqual(Defaults.recordingSavePreference, .gif)
        defaults.removeObject(forKey: "recordingSaveFormat")
        XCTAssertEqual(Defaults.recordingSavePreference, .mp4)
    }
}

final class CommandTapTests: XCTestCase {
    private func sample(_ down: Bool, _ t: TimeInterval) -> KeyMonitor.ModifierSample {
        KeyMonitor.ModifierSample(commandIsDown: down, hasDisruptiveModifiers: false, eventUptime: t)
    }

    func testQuickDoubleTapTriggersAndPrefetches() {
        var triggers = 0, prefetches = 0
        let monitor = KeyMonitor(onTrigger: { _ in triggers += 1 }, monitoring: false)
        monitor.onFirstTapReleased = { prefetches += 1 }
        monitor.handleModifierSample(sample(true, 10.00))
        monitor.handleModifierSample(sample(false, 10.06))
        monitor.handleModifierSample(sample(true, 10.15))
        let done = expectation(description: "trigger runs on the main run loop")
        DispatchQueue.main.async { done.fulfill() }
        wait(for: [done], timeout: 1)
        XCTAssertEqual(prefetches, 1)
        XCTAssertEqual(triggers, 1)
    }

    func testCommandClicksAreNotTaps() {
        var triggers = 0, prefetches = 0
        let monitor = KeyMonitor(onTrigger: { _ in triggers += 1 }, monitoring: false)
        monitor.onFirstTapReleased = { prefetches += 1 }
        monitor.handleModifierSample(sample(true, 20.00))
        monitor.noteMouseDown()
        monitor.handleModifierSample(sample(false, 20.06))
        monitor.handleModifierSample(sample(true, 20.15))
        monitor.noteMouseDown()
        monitor.handleModifierSample(sample(false, 20.20))
        let done = expectation(description: "main run loop drained")
        DispatchQueue.main.async { done.fulfill() }
        wait(for: [done], timeout: 1)
        XCTAssertEqual(prefetches, 0, "a ⌘-click must not start a speculative snapshot")
        XCTAssertEqual(triggers, 0, "two quick ⌘-clicks must not take a screenshot")
    }
}
