import AppKit
import XCTest
@testable import capcap

@MainActor
final class NumberAnnotationSizeTests: XCTestCase {
    func testDefaultSizePreservesExistingBadgeGeometry() {
        let annotation = NumberAnnotation(
            center: NSPoint(x: 100, y: 80),
            number: 1,
            color: .systemRed
        )

        XCTAssertEqual(annotation.size, 5)
        XCTAssertEqual(annotation.radius, 14)
        XCTAssertEqual(annotation.circleRect.width, 28)
        XCTAssertEqual(annotation.arrowMinDistance, 20)
    }

    func testSizeScalesBadgeAndClampsToSliderRange() {
        let maximum = NumberAnnotation(
            center: .zero,
            number: 1,
            color: .systemRed,
            size: 30
        )
        let minimum = NumberAnnotation(
            center: .zero,
            number: 1,
            color: .systemRed,
            size: 0
        )

        XCTAssertEqual(maximum.size, 25)
        XCTAssertEqual(maximum.radius, 70)
        XCTAssertEqual(maximum.circleRect.width, 140)
        XCTAssertEqual(maximum.arrowMinDistance, 100)
        XCTAssertEqual(minimum.size, 1)
        XCTAssertEqual(minimum.radius, 2.8, accuracy: 0.001)
    }

    func testNumberMutationsPreserveSize() throws {
        let annotation = NumberAnnotation(
            center: NSPoint(x: 40, y: 50),
            tip: NSPoint(x: 120, y: 90),
            controlPoint: NSPoint(x: 75, y: 110),
            number: 4,
            color: .systemBlue,
            size: 12
        )

        XCTAssertEqual(annotation.withNumber(5).size, 12)
        XCTAssertEqual(annotation.withTip(nil).size, 12)
        XCTAssertEqual(annotation.withControlPoint(nil).size, 12)
        XCTAssertEqual(try XCTUnwrap(annotation.withColor(.systemGreen) as? NumberAnnotation).size, 12)
        XCTAssertEqual(
            try XCTUnwrap(annotation.translated(by: NSPoint(x: 5, y: -3)) as? NumberAnnotation).size,
            12
        )
    }

    func testCanvasUsesCurrentNumberSizeAndUndoRestoresSliderMutation() throws {
        let canvas = EditCanvasView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        let window = NSWindow(
            contentRect: canvas.bounds,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = canvas
        canvas.currentNumberSize = 25
        canvas.activeTool = .numbered

        let center = NSPoint(x: 120, y: 100)
        canvas.mouseDown(with: try mouseEvent(type: .leftMouseDown, point: center))
        canvas.mouseUp(with: try mouseEvent(type: .leftMouseUp, point: center))
        XCTAssertTrue(canvas.selectAllAnnotations())

        var annotation = try XCTUnwrap(canvas.selectedAnnotation as? NumberAnnotation)
        XCTAssertEqual(annotation.size, 25)

        canvas.beginSelectionAdjustment()
        canvas.mutateSelectedAnnotationLive { $0.withLineWidth(10) }
        canvas.commitSelectionAdjustment()
        annotation = try XCTUnwrap(canvas.selectedAnnotation as? NumberAnnotation)
        XCTAssertEqual(annotation.size, 10)

        XCTAssertTrue(canvas.undo())
        annotation = try XCTUnwrap(canvas.selectedAnnotation as? NumberAnnotation)
        XCTAssertEqual(annotation.size, 25)
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
