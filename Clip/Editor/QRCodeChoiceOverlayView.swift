import AppKit

struct QRCodeChoice {
    let payload: String
    let anchorRect: NSRect
}

final class QRCodeChoiceOverlayView: NSView {
    private let choices: [QRCodeChoice]
    private let onChoose: (QRCodeChoice) -> Void
    private var choiceButtons: [QRCodeChoiceButton] = []

    init(frame frameRect: NSRect, choices: [QRCodeChoice], onChoose: @escaping (QRCodeChoice) -> Void) {
        self.choices = choices
        self.onChoose = onChoose
        super.init(frame: frameRect)
        autoresizingMask = [.width, .height]
        setupButtons()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, alphaValue > 0 else { return nil }
        let localPoint = convert(point, from: superview)
        guard bounds.contains(localPoint) else { return nil }
        for subview in subviews.reversed() {
            if let hit = subview.hitTest(localPoint) {
                return hit
            }
        }
        return nil
    }

    override func layout() {
        super.layout()
        layoutButtons()
    }

    private func setupButtons() {
        for choice in choices {
            let button = QRCodeChoiceButton(frame: .zero)
            button.toolTip = L10n.copyQRCodeContent
            button.onClick = { [weak self] in
                self?.onChoose(choice)
            }
            choiceButtons.append(button)
            addSubview(button)
        }
        layoutButtons()
    }

    private func layoutButtons() {
        let size: CGFloat = 64
        let margin = size / 2 + 4
        for (index, choice) in choices.enumerated() where index < choiceButtons.count {
            var center = NSPoint(x: choice.anchorRect.midX, y: choice.anchorRect.midY)
            if bounds.width > size {
                center.x = min(max(center.x, margin), bounds.width - margin)
            }
            if bounds.height > size {
                center.y = min(max(center.y, margin), bounds.height - margin)
            }
            choiceButtons[index].frame = NSRect(
                x: center.x - size / 2,
                y: center.y - size / 2,
                width: size,
                height: size
            )
        }
    }
}

private final class QRCodeChoiceButton: NSButton {
    var onClick: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        title = ""
        isBordered = false
        bezelStyle = .regularSquare
        setButtonType(.momentaryChange)
        target = self
        action = #selector(clicked)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let outerRect = bounds.insetBy(dx: 2, dy: 2)
        let innerRect = bounds.insetBy(dx: 8, dy: 8)

        NSGraphicsContext.saveGraphicsState()
        let glow = NSShadow()
        glow.shadowBlurRadius = 12
        glow.shadowColor = NSColor.systemGreen.withAlphaComponent(0.35)
        glow.shadowOffset = .zero
        glow.set()
        NSColor.systemGreen.withAlphaComponent(0.18).setFill()
        NSBezierPath(ovalIn: outerRect).fill()
        NSGraphicsContext.restoreGraphicsState()

        let fillColor = isHighlighted
            ? NSColor(red: 0.02, green: 0.58, blue: 0.22, alpha: 1.0)
            : NSColor(red: 0.02, green: 0.78, blue: 0.32, alpha: 1.0)
        fillColor.setFill()
        NSBezierPath(ovalIn: innerRect).fill()

        NSColor.white.withAlphaComponent(0.72).setStroke()
        let ring = NSBezierPath(ovalIn: innerRect.insetBy(dx: 1.5, dy: 1.5))
        ring.lineWidth = 1.5
        ring.stroke()

        context.saveGState()
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(5)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        let midX = bounds.midX
        let midY = bounds.midY
        context.move(to: CGPoint(x: midX - 15, y: midY))
        context.addLine(to: CGPoint(x: midX + 13, y: midY))
        context.move(to: CGPoint(x: midX + 2, y: midY + 11))
        context.addLine(to: CGPoint(x: midX + 13, y: midY))
        context.addLine(to: CGPoint(x: midX + 2, y: midY - 11))
        context.strokePath()
        context.restoreGState()
    }

    @objc private func clicked() {
        onClick?()
    }
}
