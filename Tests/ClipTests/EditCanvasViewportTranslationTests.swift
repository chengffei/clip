import AppKit
import XCTest
@testable import capcap

@MainActor
final class EditCanvasViewportTranslationTests: XCTestCase {
    func testViewportOriginChangeKeepsAnnotationAtSameScreenPosition() throws {
        let canvas = EditCanvasView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        XCTAssertTrue(canvas.insertEmoji("🎯"))
        let original = try XCTUnwrap(canvas.selectedAnnotation as? EmojiAnnotation)
        let oldViewport = NSRect(x: 100, y: 80, width: 320, height: 240)
        let newViewport = NSRect(x: 124, y: 61, width: 360, height: 280)

        canvas.preserveAnnotationScreenPositions(from: oldViewport, to: newViewport)

        let translated = try XCTUnwrap(canvas.selectedAnnotation as? EmojiAnnotation)
        XCTAssertEqual(translated.rect.minX, original.rect.minX - 24, accuracy: 0.001)
        XCTAssertEqual(translated.rect.minY, original.rect.minY + 19, accuracy: 0.001)
        XCTAssertEqual(newViewport.minX + translated.rect.minX, oldViewport.minX + original.rect.minX, accuracy: 0.001)
        XCTAssertEqual(newViewport.minY + translated.rect.minY, oldViewport.minY + original.rect.minY, accuracy: 0.001)
    }

    func testViewportSizeChangeFromMaximumEdgesDoesNotMoveAnnotation() throws {
        let canvas = EditCanvasView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        XCTAssertTrue(canvas.insertEmoji("🎯"))
        let original = try XCTUnwrap(canvas.selectedAnnotation as? EmojiAnnotation)

        canvas.preserveAnnotationScreenPositions(
            from: NSRect(x: 100, y: 80, width: 320, height: 240),
            to: NSRect(x: 100, y: 80, width: 400, height: 300)
        )

        let unchanged = try XCTUnwrap(canvas.selectedAnnotation as? EmojiAnnotation)
        XCTAssertEqual(unchanged.rect, original.rect)
    }

    func testUndoRedoHistoryUsesTranslatedViewportCoordinates() throws {
        let canvas = EditCanvasView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        XCTAssertTrue(canvas.insertEmoji("🎯"))
        canvas.mutateSelectedAnnotationAtomic {
            $0.translated(by: NSPoint(x: 8, y: 6))
        }
        let movedBeforeTranslation = try XCTUnwrap(canvas.selectedAnnotation as? EmojiAnnotation)

        canvas.preserveAnnotationScreenPositions(
            from: NSRect(x: 40, y: 30, width: 320, height: 240),
            to: NSRect(x: 55, y: 42, width: 320, height: 240)
        )

        XCTAssertTrue(canvas.undo())
        XCTAssertTrue(canvas.redo())
        let movedAfterRedo = try XCTUnwrap(canvas.selectedAnnotation as? EmojiAnnotation)
        XCTAssertEqual(movedAfterRedo.rect.minX, movedBeforeTranslation.rect.minX - 15, accuracy: 0.001)
        XCTAssertEqual(movedAfterRedo.rect.minY, movedBeforeTranslation.rect.minY - 12, accuracy: 0.001)
    }
}
