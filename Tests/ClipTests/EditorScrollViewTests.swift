import AppKit
import XCTest
@testable import capcap

@MainActor
final class EditorScrollViewTests: XCTestCase {
    func testScreenBackedAnnotationsDoNotScroll() throws {
        let scroll = EditorScrollView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        let canvas = EditCanvasView(frame: NSRect(x: 0, y: 0, width: 200, height: 500))
        scroll.documentView = canvas
        scroll.editorCanvasView = canvas
        let origin = scroll.contentView.bounds.origin
        let cgEvent = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil, units: .pixel,
            wheelCount: 2, wheel1: -40, wheel2: 20, wheel3: 0
        ))
        canvas.scrollWheel(with: try XCTUnwrap(NSEvent(cgEvent: cgEvent)))
        XCTAssertEqual(scroll.contentView.bounds.origin, origin)
        XCTAssertEqual(scroll.horizontalScrollElasticity, .none)
        XCTAssertEqual(scroll.verticalScrollElasticity, .none)
    }

    func testTallImageCanStillScroll() throws {
        let scroll = EditorScrollView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        let canvas = EditCanvasView(frame: NSRect(x: 0, y: 0, width: 200, height: 500))
        canvas.overrideBaseImage = NSImage(size: canvas.frame.size)
        scroll.documentView = canvas
        scroll.editorCanvasView = canvas
        scroll.hasVerticalScroller = true
        let window = NSWindow(contentRect: scroll.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = scroll
        defer { window.orderOut(nil) }
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 200))
        let origin = scroll.contentView.bounds.origin
        let cgEvent = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil, units: .pixel,
            wheelCount: 1, wheel1: -40, wheel2: 0, wheel3: 0
        ))
        canvas.scrollWheel(with: try XCTUnwrap(NSEvent(cgEvent: cgEvent)))
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertNotEqual(scroll.contentView.bounds.origin.y, origin.y)
        XCTAssertEqual(scroll.contentView.bounds.origin.x, 0)
    }
}
