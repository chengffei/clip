import AppKit
import XCTest
@testable import capcap

@MainActor
final class EditCanvasDoubleClickTests: XCTestCase {
    func testConfirmDoubleClickRestoresStateBeforeFirstClickMutation() {
        let canvas = EditCanvasView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        let point = NSPoint(x: 120, y: 100)

        XCTAssertFalse(canvas.handlePotentialConfirmDoubleClick(clickCount: 1, at: point))
        XCTAssertTrue(canvas.insertEmoji("✅"))
        XCTAssertTrue(canvas.canUndo)

        XCTAssertTrue(canvas.handlePotentialConfirmDoubleClick(clickCount: 2, at: point))
        XCTAssertFalse(canvas.canUndo)
        XCTAssertFalse(canvas.selectAllAnnotations())
    }

    func testConfirmDoubleClickCancelsTextEditorCreatedByFirstClick() throws {
        let canvas = EditCanvasView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        let window = NSWindow(
            contentRect: canvas.bounds,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = canvas
        canvas.activeTool = .text
        let point = NSPoint(x: 120, y: 100)

        XCTAssertFalse(canvas.handlePotentialConfirmDoubleClick(clickCount: 1, at: point))
        canvas.mouseDown(with: try mouseEvent(type: .leftMouseDown, point: point))
        canvas.mouseUp(with: try mouseEvent(type: .leftMouseUp, point: point))
        XCTAssertTrue(canvas.isTextEditing)

        XCTAssertTrue(canvas.handlePotentialConfirmDoubleClick(clickCount: 2, at: point))
        XCTAssertFalse(canvas.isTextEditing)
        XCTAssertFalse(canvas.canUndo)
    }

    private func mouseEvent(type: NSEvent.EventType, point: NSPoint) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(
            with: type,
            location: point,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ))
    }
}
