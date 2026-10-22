import AppKit
import XCTest
@testable import capcap

@MainActor
final class TextAnnotationCalloutLeaderTests: XCTestCase {
    func testSelectedTextCalloutCanPullOutSecondLeaderWithoutReplacingCreationLeader() throws {
        let canvas = EditCanvasView(frame: NSRect(x: 0, y: 0, width: 360, height: 260))
        let window = NSWindow(
            contentRect: canvas.bounds,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = canvas
        canvas.currentTextCallout = true
        canvas.activeTool = .text

        let start = NSPoint(x: 160, y: 160)
        let creationTip = NSPoint(x: 270, y: 80)
        canvas.mouseDown(with: try mouseEvent(type: .leftMouseDown, point: start))
        canvas.mouseDragged(with: try mouseEvent(type: .leftMouseDragged, point: creationTip))
        canvas.mouseUp(with: try mouseEvent(type: .leftMouseUp, point: creationTip))

        let field = try XCTUnwrap(canvas.subviews.compactMap { $0 as? EditableTextField }.first)
        field.stringValue = "Note"
        canvas.commitActiveTextEditing()

        XCTAssertTrue(canvas.selectAllAnnotations())
        var annotation = try XCTUnwrap(canvas.selectedAnnotation as? TextAnnotation)
        XCTAssertEqual(annotation.calloutTip, creationTip)
        XCTAssertTrue(annotation.hasCalloutArrow)
        XCTAssertNil(annotation.secondCalloutTip)
        XCTAssertFalse(annotation.hasSecondCalloutArrow)

        let secondTip = NSPoint(x: 70, y: 205)
        canvas.mouseDown(with: try mouseEvent(
            type: .leftMouseDown,
            point: annotation.secondCalloutHandlePoint
        ))
        canvas.mouseDragged(with: try mouseEvent(type: .leftMouseDragged, point: secondTip))
        canvas.mouseUp(with: try mouseEvent(type: .leftMouseUp, point: secondTip))

        annotation = try XCTUnwrap(canvas.selectedAnnotation as? TextAnnotation)
        XCTAssertEqual(annotation.calloutTip, creationTip)
        XCTAssertEqual(annotation.secondCalloutTip, secondTip)
        XCTAssertTrue(annotation.hasCalloutArrow)
        XCTAssertTrue(annotation.hasSecondCalloutArrow)

        XCTAssertTrue(canvas.undo())
        annotation = try XCTUnwrap(canvas.selectedAnnotation as? TextAnnotation)
        XCTAssertEqual(annotation.calloutTip, creationTip)
        XCTAssertNil(annotation.secondCalloutTip)
    }

    func testSecondLeaderParticipatesInBoundsHitTestingAndTranslation() throws {
        let annotation = TextAnnotation(
            text: "Note",
            origin: NSPoint(x: 120, y: 120),
            color: .systemBlue,
            fontSize: 24,
            hasCallout: true,
            calloutTip: NSPoint(x: 240, y: 70),
            secondCalloutTip: NSPoint(x: 55, y: 80)
        )
        let firstAnchor = annotation.calloutAnchorPoint(for: annotation.calloutTip)
        let secondAnchor = annotation.calloutAnchorPoint(for: annotation.secondCalloutTip)
        let firstHitSamples = pointsAlongLeader(from: firstAnchor, to: annotation.calloutTip!)
            .map(annotation.containsPoint)
        let secondHitSamples = pointsAlongLeader(from: secondAnchor, to: annotation.secondCalloutTip!)
            .map(annotation.containsPoint)

        XCTAssertTrue(annotation.hasCalloutArrow)
        XCTAssertTrue(annotation.hasSecondCalloutArrow)
        XCTAssertTrue(firstHitSamples.contains(true), "\(firstHitSamples)")
        XCTAssertTrue(secondHitSamples.contains(true), "\(secondHitSamples)")
        XCTAssertTrue(annotation.boundingRect.contains(annotation.calloutTip!))
        XCTAssertTrue(annotation.boundingRect.contains(annotation.secondCalloutTip!))

        let translated = try XCTUnwrap(
            annotation.translated(by: NSPoint(x: 12, y: -8)) as? TextAnnotation
        )
        XCTAssertEqual(translated.origin, NSPoint(x: 132, y: 112))
        XCTAssertEqual(translated.calloutTip, NSPoint(x: 252, y: 62))
        XCTAssertEqual(translated.secondCalloutTip, NSPoint(x: 67, y: 72))
    }

    private func pointsAlongLeader(from start: NSPoint, to end: NSPoint) -> [NSPoint] {
        [0.2, 0.4, 0.6, 0.8].map { progress in
            NSPoint(
                x: start.x + (end.x - start.x) * progress,
                y: start.y + (end.y - start.y) * progress
            )
        }
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
