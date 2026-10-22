import AppKit

final class PasteableTextField: NSTextField {
    var onFocus: ((PasteableTextField) -> Void)?

    override func mouseDown(with event: NSEvent) {
        onFocus?(self)
        super.mouseDown(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        let didBecome = super.becomeFirstResponder()
        if didBecome {
            onFocus?(self)
        }
        return didBecome
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if dispatchEditingShortcut(event) { return true }
        return super.performKeyEquivalent(with: event)
    }
}
