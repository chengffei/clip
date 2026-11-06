import AppKit

/// Single-instance hover tooltip used by the editor toolbar
/// A capsule chip on the same material as the toolbar (Liquid Glass, or the
/// opaque plate with Reduce Transparency). It names the action and, when one
/// is given, shows the keyboard shortcut after it in secondary text.
final class ToolTipWindow: NSPanel {
    private static var current: ToolTipWindow?
    private static var pendingWorkItem: DispatchWorkItem?

    /// `anchor` is the screen-space rect of the hovered control. The tip
    /// pops above it, horizontally centered.
    static func show(text: String, shortcut: String? = nil, anchor: NSRect, delay: TimeInterval = 0.35) {
        cancelPending()
        let work = DispatchWorkItem {
            present(text: text, shortcut: shortcut, anchor: anchor)
        }
        pendingWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    static func hide() {
        cancelPending()
        current?.orderOut(nil)
        current = nil
    }

    private static func cancelPending() {
        pendingWorkItem?.cancel()
        pendingWorkItem = nil
    }

    private static func present(text: String, shortcut: String?, anchor: NSRect) {
        current?.orderOut(nil)

        let tip = ToolTipWindow(text: text, shortcut: shortcut)
        current = tip

        let gap: CGFloat = 6
        let x = anchor.midX - tip.frame.width / 2
        let y = anchor.maxY + gap
        tip.setFrameOrigin(NSPoint(x: x, y: y))

        tip.alphaValue = 0
        tip.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            tip.animator().alphaValue = 1.0
        }
    }

    private init(text: String, shortcut: String?) {
        let label = ToolTipContentView.attributedText(text: text, shortcut: shortcut)
        let size = NSSize(
            width: ceil(label.size().width) + ToolTipContentView.horizontalPadding * 2,
            height: ToolTipContentView.height
        )

        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .screenSaver + 4
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        let content = ToolTipContentView(frame: NSRect(origin: .zero, size: size), label: label)
        contentView = CaptureChrome.chipContentView(content: content, cornerRadius: size.height / 2)
    }
}

private final class ToolTipContentView: NSView {
    static let height: CGFloat = 22
    static let horizontalPadding: CGFloat = 9

    static func attributedText(text: String, shortcut: String?) -> NSAttributedString {
        let font = NSFont.systemFont(ofSize: 11, weight: .medium)
        let out = NSMutableAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: NSColor.labelColor,
        ])
        if let shortcut, !shortcut.isEmpty {
            out.append(NSAttributedString(string: "  " + shortcut, attributes: [
                .font: Brand.monoDigits(11, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]))
        }
        return out
    }

    private let label: NSAttributedString

    init(frame: NSRect, label: NSAttributedString) {
        self.label = label
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        CaptureChrome.drawChipPlateIfNeeded(for: self, cornerRadius: bounds.height / 2)
        let size = label.size()
        label.draw(at: NSPoint(
            x: ((bounds.width - size.width) / 2).rounded(),
            y: ((bounds.height - size.height) / 2).rounded()
        ))
    }
}
