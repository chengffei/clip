import AppKit

/// Translucent fullscreen-overlay-free countdown shown before a delayed capture.
/// Displays a large high-contrast digit on a rounded adaptive plate centered on
/// the cursor's screen. Esc cancels; on natural expiry calls `onFinish`.
final class CountdownWindow: NSPanel {
    private static var current: CountdownWindow?

    static func start(seconds: Int, onFinish: @escaping () -> Void, onCancel: @escaping () -> Void) {
        current?.cancelImmediately()

        let cursorPoint = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(cursorPoint) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else {
            onFinish()
            return
        }

        let panel = CountdownWindow(seconds: max(1, seconds), screen: screen,
                                    onFinish: onFinish, onCancel: onCancel)
        current = panel
        panel.begin()
    }

    private let totalSeconds: Int
    private var remaining: Int
    private var timer: Timer?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private let onFinish: () -> Void
    private let onCancel: () -> Void
    private let plate: CountdownPlateView
    private var didEnd = false

    private init(seconds: Int, screen: NSScreen,
                 onFinish: @escaping () -> Void,
                 onCancel: @escaping () -> Void) {
        self.totalSeconds = seconds
        self.remaining = seconds
        self.onFinish = onFinish
        self.onCancel = onCancel

        let side: CGFloat = 200
        let origin = NSPoint(
            x: screen.frame.midX - side / 2,
            y: screen.frame.midY - side / 2
        )
        let rect = NSRect(origin: origin, size: NSSize(width: side, height: side))
        self.plate = CountdownPlateView(frame: NSRect(origin: .zero, size: rect.size))

        super.init(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .screenSaver + 4
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        contentView = plate
        plate.setDigit(remaining, animated: false)
    }

    private func begin() {
        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            self.animator().alphaValue = 1.0
        }

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.cancel()
                return nil
            }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.cancel()
            }
        }
    }

    private func tick() {
        remaining -= 1
        if remaining <= 0 {
            finish()
        } else {
            plate.setDigit(remaining, animated: true)
        }
    }

    private func finish() {
        guard !didEnd else { return }
        didEnd = true
        teardown()
        // Hide and give the WindowServer a beat to actually remove the panel
        // from screen before capture snapshots — otherwise the trailing "1"
        // gets baked into the screenshot's underlying snapshot.
        orderOut(nil)
        if CountdownWindow.current === self { CountdownWindow.current = nil }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [onFinish] in
            onFinish()
        }
    }

    private func cancel() {
        guard !didEnd else { return }
        didEnd = true
        teardown()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            self.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self else { return }
            self.orderOut(nil)
            if CountdownWindow.current === self { CountdownWindow.current = nil }
            self.onCancel()
        })
    }

    private func cancelImmediately() {
        guard !didEnd else { return }
        didEnd = true
        teardown()
        orderOut(nil)
        if CountdownWindow.current === self { CountdownWindow.current = nil }
        onCancel()
    }

    private func teardown() {
        timer?.invalidate()
        timer = nil
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class CountdownPlateView: NSView {
    private let digitLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 28
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        applyAppearance()

        digitLabel.translatesAutoresizingMaskIntoConstraints = false
        digitLabel.alignment = .center
        digitLabel.textColor = .labelColor
        digitLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 120, weight: .semibold)
        digitLabel.isBezeled = false
        digitLabel.drawsBackground = false
        digitLabel.isEditable = false
        digitLabel.isSelectable = false
        addSubview(digitLabel)
        NSLayoutConstraint.activate([
            digitLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            digitLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyAppearance()
    }

    private func applyAppearance() {
        layer?.backgroundColor = AdaptiveChrome.resolvedCGColor(
            AdaptiveChrome.floatingBackground,
            for: effectiveAppearance
        )
        layer?.borderColor = AdaptiveChrome.resolvedCGColor(
            AdaptiveChrome.border,
            for: effectiveAppearance
        )
        digitLabel.textColor = .labelColor
    }

    func setDigit(_ value: Int, animated: Bool) {
        let newText = "\(value)"
        guard animated else {
            digitLabel.stringValue = newText
            return
        }
        // Fade-out current digit, swap text, fade-in.
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            digitLabel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self else { return }
            self.digitLabel.stringValue = newText
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                self.digitLabel.animator().alphaValue = 1.0
            }
        })
    }
}
