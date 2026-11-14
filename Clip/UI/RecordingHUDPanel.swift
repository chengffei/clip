import AppKit

final class RecordingHUDPanel: NSPanel {
    var onStopRecording: (() -> Void)?
    var onPauseRecording: (() -> Void)?
    var onResumeRecording: (() -> Void)?

    private let containerView = RecordingHUDContainerView()
    /// Liquid Glass capsule; every control lives in `glass.contentView`.
    private let glass = GlassChromeView()
    private let stopButton = RecordingStopButton()
    private let pauseButton = NSButton()
    private let recordDot = NSImageView()
    private let timeLabel = NSTextField(labelWithString: "00:00")
    private let dragHandle = NSImageView()
    private(set) var isPaused = false
    fileprivate(set) var userHasDragged = false

    private static let hudSize = NSSize(width: 164, height: FloatingControlChrome.height)

    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.hudSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .statusBar + 2
        hidesOnDeactivate = false
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        containerView.panel = self
        contentView = containerView
        // Size the glass after the container has its real frame, so
        // autoresizing starts from matching sizes.
        glass.frame = containerView.bounds
        glass.autoresizingMask = [.width, .height]
        containerView.addSubview(glass)

        setupControls()
        layoutControls()
    }

    override var canBecomeKey: Bool { false }

    func update(elapsedSeconds: Int) {
        let minutes = elapsedSeconds / 60
        let seconds = elapsedSeconds % 60
        timeLabel.stringValue = String(format: "%02d:%02d", minutes, seconds)
        layoutControls()
    }

    func setPaused(_ paused: Bool) {
        isPaused = paused
        // Red dot while capturing; a neutral dot while paused (no extra accent).
        recordDot.contentTintColor = paused ? .tertiaryLabelColor : Brand.alert
        pauseButton.toolTip = paused ? L10n.recordingResume : L10n.recordingPause
        updatePauseIcon()
    }

    func positionOnScreen(relativeTo screenRect: NSRect, screen: NSScreen?) {
        setFrameOrigin(FloatingControlChrome.origin(
            for: Self.hudSize,
            relativeTo: screenRect,
            visibleFrame: screen?.visibleFrame
        ))
    }

    private func setupControls() {
        let host = glass.contentView

        stopButton.toolTip = L10n.recordingStop
        stopButton.setAccessibilityLabel(L10n.recordingStop)
        stopButton.target = self
        stopButton.action = #selector(stopClicked)
        host.addSubview(stopButton)

        configureGlyphButton(pauseButton)
        pauseButton.target = self
        pauseButton.action = #selector(pauseClicked)
        host.addSubview(pauseButton)
        updatePauseIcon()

        recordDot.image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 7, weight: .regular))
        recordDot.contentTintColor = Brand.alert
        recordDot.imageScaling = .scaleNone
        recordDot.setAccessibilityElement(false)
        host.addSubview(recordDot)

        // SF Pro with monospaced digits so the timer never jitters as it ticks.
        timeLabel.font = Brand.monoDigits(13, weight: .medium)
        timeLabel.textColor = .labelColor
        timeLabel.isBezeled = false
        timeLabel.drawsBackground = false
        timeLabel.isEditable = false
        host.addSubview(timeLabel)

        dragHandle.image = NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .regular))
        dragHandle.contentTintColor = .tertiaryLabelColor
        dragHandle.imageScaling = .scaleNone
        host.addSubview(dragHandle)
    }

    private func configureGlyphButton(_ button: NSButton) {
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        button.contentTintColor = .labelColor
    }

    private static func glyph(_ symbol: String, _ description: String?) -> NSImage? {
        NSImage(systemSymbolName: symbol, accessibilityDescription: description)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(
                pointSize: Brand.glassControlSymbolSize,
                weight: Brand.glassControlSymbolWeight
            ))
    }

    private func layoutControls() {
        let buttonSize = FloatingControlChrome.buttonSide
        let height = Self.hudSize.height
        let buttonY = (height - buttonSize) / 2
        // Inset so the round stop button sits concentric with the capsule end.
        let padding = (height - buttonSize) / 2

        stopButton.frame = NSRect(x: padding, y: buttonY, width: buttonSize, height: buttonSize)
        pauseButton.frame = NSRect(x: stopButton.frame.maxX + 4, y: buttonY, width: buttonSize, height: buttonSize)

        timeLabel.sizeToFit()
        recordDot.frame = NSRect(x: pauseButton.frame.maxX + 6, y: (height - 10) / 2, width: 10, height: 10)
        timeLabel.frame.origin = NSPoint(
            x: recordDot.frame.maxX + 4,
            y: ((height - timeLabel.frame.height) / 2).rounded()
        )

        dragHandle.frame = NSRect(x: Self.hudSize.width - 30, y: (height - 16) / 2, width: 20, height: 16)
    }

    private func updatePauseIcon() {
        let title = isPaused ? L10n.recordingResume : L10n.recordingPause
        pauseButton.image = Self.glyph(isPaused ? "play.fill" : "pause.fill", title)
        pauseButton.setAccessibilityLabel(title)
    }

    @objc private func stopClicked() {
        onStopRecording?()
    }

    @objc private func pauseClicked() {
        if isPaused {
            onResumeRecording?()
        } else {
            onPauseRecording?()
        }
    }

    /// Right-click on the HUD: every HUD control is also a menu command.
    func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        let pause = NSMenuItem(
            title: isPaused ? L10n.recordingResume : L10n.recordingPause,
            action: #selector(pauseClicked),
            keyEquivalent: ""
        )
        pause.target = self
        menu.addItem(pause)
        let stop = NSMenuItem(title: L10n.recordingStop, action: #selector(stopClicked), keyEquivalent: "")
        stop.target = self
        menu.addItem(stop)
        return menu
    }
}

private final class RecordingHUDContainerView: NSView {
    weak var panel: RecordingHUDPanel?
    private var dragOffset: NSPoint = .zero
    private var isDragging = false
    private var trackingArea: NSTrackingArea?

    override func menu(for event: NSEvent) -> NSMenu? {
        panel?.makeContextMenu()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }

    override func cursorUpdate(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        isInDragZone(point) ? NSCursor.openHand.set() : NSCursor.arrow.set()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard isInDragZone(point) else { return }
        isDragging = true
        let mouse = NSEvent.mouseLocation
        let origin = panel?.frame.origin ?? .zero
        dragOffset = NSPoint(x: mouse.x - origin.x, y: mouse.y - origin.y)
        NSCursor.closedHand.set()
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging, let panel else { return }
        panel.userHasDragged = true
        let mouse = NSEvent.mouseLocation
        panel.setFrameOrigin(NSPoint(x: mouse.x - dragOffset.x, y: mouse.y - dragOffset.y))
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
        let point = convert(event.locationInWindow, from: nil)
        isInDragZone(point) ? NSCursor.openHand.set() : NSCursor.arrow.set()
    }

    private func isInDragZone(_ point: NSPoint) -> Bool {
        point.x >= bounds.maxX - 32
    }
}

/// The HUD's primary action: a filled red circle carrying the white
/// `stop.fill` symbol, the same record/stop semantics the system recording
/// controls use. Darkens while pressed so the click registers visually.
private final class RecordingStopButton: NSButton {
    init() {
        super.init(frame: .zero)
        title = ""
        isBordered = false
        bezelStyle = .regularSquare
        setButtonType(.momentaryChange)
        imagePosition = .imageOnly
        imageScaling = .scaleNone
        image = NSImage(systemSymbolName: "stop.fill", accessibilityDescription: L10n.recordingStop)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 10, weight: .bold))
        contentTintColor = Brand.onAccent
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        let fill = isHighlighted
            ? (Brand.alert.blended(withFraction: 0.2, of: .black) ?? Brand.alert)
            : Brand.alert
        fill.setFill()
        NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1)).fill()
        super.draw(dirtyRect)
    }
}
