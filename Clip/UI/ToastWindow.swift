import AppKit

class ToastWindow: NSPanel {
    private static var current: ToastWindow?

    static var captureExcludedWindowNumbers: [CGWindowID] {
        if Thread.isMainThread {
            return captureExcludedWindowNumbersOnMain()
        }
        return DispatchQueue.main.sync {
            captureExcludedWindowNumbersOnMain()
        }
    }

    /// Shows a transient toast. When `topAnchor` is set (a point in screen
    /// coordinates), the toast hangs just below that point with its horizontal
    /// center aligned to it — used to pin the hint to the top-center of a
    /// selection. When `centerAnchor` is set, the toast is centered on that
    /// point — used to place the hint in the middle of a selection. Otherwise
    /// the toast is centered on `screen`.
    static func show(
        message: String = L10n.copiedToClipboard,
        on screen: NSScreen? = nil,
        topAnchor: NSPoint? = nil,
        centerAnchor: NSPoint? = nil,
        duration: TimeInterval = 1.5
    ) {
        current?.orderOut(nil)

        let toast = ToastWindow(message: message)
        current = toast

        if let anchor = topAnchor {
            let x = anchor.x - toast.frame.width / 2
            let y = anchor.y - toast.frame.height - 12
            toast.setFrameOrigin(NSPoint(x: x, y: y))
        } else if let anchor = centerAnchor {
            let x = anchor.x - toast.frame.width / 2
            let y = anchor.y - toast.frame.height / 2
            toast.setFrameOrigin(NSPoint(x: x, y: y))
        } else if let screen = screen ?? NSScreen.main {
            let x = screen.frame.midX - toast.frame.width / 2
            let y = screen.frame.midY - toast.frame.height / 2
            toast.setFrameOrigin(NSPoint(x: x, y: y))
        }

        toast.alphaValue = 0
        toast.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            toast.animator().alphaValue = 1.0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.3
                toast.animator().alphaValue = 0.0
            }, completionHandler: {
                toast.orderOut(nil)
                if current === toast { current = nil }
            })
        }
    }

    /// Immediately hides any visible toast. Safe to call when none is showing.
    static func dismiss() {
        _ = dismissForCaptureIfNeeded()
    }

    @discardableResult
    static func dismissForCaptureIfNeeded() -> Bool {
        if Thread.isMainThread {
            return dismissForCaptureIfNeededOnMain()
        }
        return DispatchQueue.main.sync {
            dismissForCaptureIfNeededOnMain()
        }
    }

    private static func captureExcludedWindowNumbersOnMain() -> [CGWindowID] {
        guard let window = current, window.isVisible else { return [] }
        let windowNumber = window.windowNumber
        guard windowNumber > 0 else { return [] }
        return [CGWindowID(windowNumber)]
    }

    private static func dismissForCaptureIfNeededOnMain() -> Bool {
        guard let window = current, window.isVisible else {
            current = nil
            return false
        }
        window.orderOut(nil)
        current = nil
        return true
    }

    private init(message: String) {
        // Measure text to size the chip
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium)
        ]
        let textSize = message.size(withAttributes: attrs)
        let size = NSSize(width: textSize.width + 24, height: 32)

        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .screenSaver + 3
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        ignoresMouseEvents = true
        sharingType = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let toastView = ToastContentView(frame: NSRect(origin: .zero, size: size), message: message)
        contentView = toastView
    }
}

private class ToastContentView: NSView {
    private let message: String

    init(frame: NSRect, message: String) {
        self.message = message
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
            .font: NSFont.systemFont(ofSize: 12, weight: .medium)
        ]
        let size = message.size(withAttributes: attrs)
        let textRect = NSRect(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
        message.draw(in: textRect, withAttributes: attrs)
    }
}
