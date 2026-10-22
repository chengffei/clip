import AppKit
import XCTest
@testable import capcap

@MainActor
final class EditableTextFieldTests: XCTestCase {
    func testMarkedTextExpandsEditorBeforeInputMethodCommitsComposition() throws {
        let field = EditableTextField(frame: NSRect(x: 20, y: 20, width: 32, height: 32))
        let font = TextAnnotation.font(forSize: 24)
        field.font = font
        field.stringValue = "你好"
        field.sizeToFitText()
        let committedTextWidth = field.frame.width
        let markedTextResize = expectation(description: "marked text resizes the editor")
        var didObserveMarkedTextResize = false
        field.onChange = {
            if field.frame.width > committedTextWidth, !didObserveMarkedTextResize {
                didObserveMarkedTextResize = true
                markedTextResize.fulfill()
            }
        }

        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: committedTextWidth, height: 32))
        editor.font = font
        editor.string = field.stringValue
        field.observeTextChanges(in: editor)
        editor.selectedRange = NSRange(location: (editor.string as NSString).length, length: 0)

        editor.setMarkedText(
            "aaaaa",
            selectedRange: NSRange(location: 5, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )

        wait(for: [markedTextResize], timeout: 1)

        XCTAssertTrue(editor.hasMarkedText())
        XCTAssertEqual(editor.string, "你好aaaaa")
        XCTAssertGreaterThan(field.frame.width, committedTextWidth)
        XCTAssertEqual(
            field.frame.width,
            TextAnnotation.editorSize(for: editor.string, font: font).width,
            accuracy: 0.5
        )

        editor.unmarkText()
        field.cancel()
    }
}
