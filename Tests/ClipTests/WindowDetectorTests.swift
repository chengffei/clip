import CoreGraphics
import XCTest
@testable import capcap

final class WindowDetectorTests: XCTestCase {
    func testWindowAtSelectsPopupMenuAboveAppWindow() {
        let detector = WindowDetector()
        detector.apply([
            DetectedWindow(
                name: "Menu",
                windowID: 100,
                layer: Int(CGWindowLevelForKey(.popUpMenuWindow)),
                frame: CGRect(x: 80, y: 90, width: 240, height: 320)
            ),
            DetectedWindow(
                name: "Editor",
                windowID: 200,
                layer: 0,
                frame: CGRect(x: 0, y: 0, width: 600, height: 400)
            )
        ])

        let detected = detector.windowAt(cgPoint: CGPoint(x: 90, y: 100))

        XCTAssertEqual(detected?.windowID, 100)
        XCTAssertTrue(detector.usesCompositedScreenBackdrop(forWindowID: 100))
    }

    func testWindowAtIgnoresCursorAboveAppWindow() {
        let detector = WindowDetector()
        detector.apply([
            DetectedWindow(
                name: "Cursor",
                windowID: 100,
                layer: Int(CGWindowLevelForKey(.cursorWindow)),
                frame: CGRect(x: 80, y: 90, width: 36, height: 51)
            ),
            DetectedWindow(
                name: "Editor",
                windowID: 200,
                layer: Int(CGWindowLevelForKey(.normalWindow)),
                frame: CGRect(x: 0, y: 0, width: 600, height: 400)
            )
        ])

        let detected = detector.windowAt(cgPoint: CGPoint(x: 90, y: 100))

        XCTAssertEqual(detected?.windowID, 200)
    }

    func testWindowAtDoesNotReturnOnlyTransientSurface() {
        let detector = WindowDetector()
        detector.apply([
            DetectedWindow(
                name: "Insertion Point",
                windowID: 300,
                layer: Int(CGWindowLevelForKey(.statusWindow)),
                frame: CGRect(x: 80, y: 90, width: 36, height: 51)
            )
        ])

        XCTAssertNil(detector.windowAt(cgPoint: CGPoint(x: 90, y: 100)))
    }
}
