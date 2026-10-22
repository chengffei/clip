import AppKit

/// A small adaptive HUD panel shown while capcap checks for, downloads, or installs
/// an update.
///
/// Unlike `ToastWindow` it persists across phases: callers advance it through
/// "checking → downloading → installing" by calling `show` repeatedly, and
/// dismiss it explicitly when the flow ends (or the app relaunches itself).
final class UpdateProgressWindow: NSPanel {
    /// What the indicator shows: an indeterminate spinner, or a determinate bar.
    enum Style: Equatable {
        case spinner
        case bar(fraction: Double)
    }

    private static var current: UpdateProgressWindow?
    private static let windowSize = NSSize(width: 320, height: 96)

    private let spinner = NSProgressIndicator()
    private let bar = NSProgressIndicator()
    private let label = NSTextField(labelWithString: "")

    // MARK: - API

    /// Shows the HUD (creating it on first use) and updates its message/style.
    /// Safe to call repeatedly to advance through phases.
    static func show(message: String, style: Style) {
        let window = current ?? UpdateProgressWindow()
        current = window
        window.apply(message: message, style: style)

        if !window.isVisible {
            window.centerOnActiveScreen()
            window.alphaValue = 0
            window.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                window.animator().alphaValue = 1
            }
        }
    }

    /// Fades out and closes the HUD. Safe to call when none is showing.
    static func dismiss() {
        guard let window = current else { return }
        current = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            window.animator().alphaValue = 0
        }, completionHandler: {
            window.spinner.stopAnimation(nil)
            window.orderOut(nil)
        })
    }

    // MARK: - Setup

    private init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.windowSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = false
        let content = HUDBackgroundView(frame: NSRect(origin: .zero, size: Self.windowSize))

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        spinner.isDisplayedWhenStopped = false

        bar.style = .bar
        bar.isIndeterminate = false
        bar.minValue = 0
        bar.maxValue = 1

        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1

        content.addSubview(spinner)
        content.addSubview(bar)
        content.addSubview(label)
        contentView = content
    }

    // MARK: - Layout

    private func apply(message: String, style: Style) {
        label.stringValue = message
        let w = Self.windowSize.width
        let h = Self.windowSize.height
        let labelHeight = label.intrinsicContentSize.height

        switch style {
        case .spinner:
            bar.isHidden = true
            spinner.isHidden = false
            spinner.startAnimation(nil)

            spinner.frame = NSRect(x: 30, y: (h - 24) / 2, width: 24, height: 24)
            label.alignment = .left
            let textX = spinner.frame.maxX + 14
            label.frame = NSRect(x: textX, y: (h - labelHeight) / 2,
                                 width: w - textX - 28, height: labelHeight)

        case .bar(let fraction):
            spinner.stopAnimation(nil)
            spinner.isHidden = true
            bar.isHidden = false
            bar.doubleValue = min(max(fraction, 0), 1)

            label.alignment = .center
            label.frame = NSRect(x: 32, y: 54, width: w - 64, height: labelHeight)
            bar.frame = NSRect(x: 32, y: 34, width: w - 64, height: 18)
        }
    }

    private func centerOnActiveScreen() {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { return }
        setFrameOrigin(NSPoint(
            x: visible.midX - Self.windowSize.width / 2,
            y: visible.midY - Self.windowSize.height / 2
        ))
    }
}

/// Draws the rounded adaptive chip behind the HUD's contents — matches the toast
/// styling used elsewhere in the app.
private final class HUDBackgroundView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1),
                                xRadius: 12, yRadius: 12)
        AdaptiveChrome.floatingBackground.setFill()
        path.fill()
        AdaptiveChrome.border.setStroke()
        path.lineWidth = 0.5
        path.stroke()
    }
}
