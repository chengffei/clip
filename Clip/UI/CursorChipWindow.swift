import AppKit

class CursorChipWindow: NSPanel {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private let chipView: ChipView

    init(text: String = L10n.dragToScreenshot) {
        let chipSize = ChipView.fittingSize(for: text)
        self.chipView = ChipView(frame: NSRect(origin: .zero, size: chipSize), text: text)
        super.init(
            contentRect: NSRect(origin: .zero, size: chipSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .screenSaver + 1
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        sharingType = .none

        contentView = chipView
    }

    func updateText(_ text: String) {
        guard chipView.text != text else { return }
        let chipSize = ChipView.fittingSize(for: text)
        setContentSize(chipSize)
        chipView.frame = NSRect(origin: .zero, size: chipSize)
        chipView.text = text
        chipView.needsDisplay = true
        updatePosition()
    }

    func show() {
        updatePosition()
        orderFrontRegardless()

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            self?.updatePosition()
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            self?.updatePosition()
            return event
        }
    }

    func dismiss() {
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
        orderOut(nil)
    }

    private func updatePosition() {
        let loc = NSEvent.mouseLocation
        setFrameOrigin(NSPoint(x: loc.x + 15, y: loc.y - 40))
    }
}

private class ChipView: NSView {
    private static let minWidth: CGFloat = 240
    private static let maxWidth: CGFloat = 560
    private static let height: CGFloat = 32
    private static let horizontalPadding: CGFloat = 28
    private static let font = NSFont.systemFont(ofSize: 12, weight: .medium)
    private static let paragraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byTruncatingTail
        return style
    }()

    var text: String

    init(frame frameRect: NSRect, text: String) {
        self.text = text
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    static func fittingSize(for text: String) -> NSSize {
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let textWidth = ceil(text.size(withAttributes: attrs).width)
        let width = min(max(minWidth, textWidth + horizontalPadding), maxWidth)
        return NSSize(width: width, height: height)
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 8, yRadius: 8)

        AdaptiveChrome.floatingBackground.setFill()
        path.fill()

        AdaptiveChrome.border.setStroke()
        path.lineWidth = 0.5
        path.stroke()

        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.labelColor,
            .font: Self.font,
            .paragraphStyle: Self.paragraphStyle
        ]
        let size = text.size(withAttributes: attrs)
        let textRect = NSRect(
            x: Self.horizontalPadding / 2,
            y: (bounds.height - size.height) / 2,
            width: bounds.width - Self.horizontalPadding,
            height: size.height
        )
        (text as NSString).draw(
            with: textRect,
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: attrs
        )
    }
}
