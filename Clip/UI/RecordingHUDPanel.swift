import AppKit

final class RecordingHUDPanel: NSPanel {
    var onStopRecording: (() -> Void)?
    var onPauseRecording: (() -> Void)?
    var onResumeRecording: (() -> Void)?
    var onToggleSystemAudio: ((Bool) -> Void)?
    var onToggleMicrophone: ((Bool) -> Void)?
    /// Right-click on the mic button picks an input device; nil = default.
    var onSelectMicrophoneDevice: ((String?) -> Void)?

    private let containerView = RecordingHUDContainerView()
    /// Liquid Glass capsule; every control lives in `glass.contentView`.
    private let glass = GlassChromeView()
    private let stopButton = RecordingStopButton()
    private let pauseButton = NSButton()
    private let recordDot = NSImageView()
    private let timeLabel = NSTextField(labelWithString: "00:00")
    private let systemAudioButton = NSButton()
    private let microphoneButton = AudioDeviceMenuButton()
    private let dragHandle = NSImageView()
    private(set) var isPaused = false
    fileprivate(set) var userHasDragged = false

    private var systemAudioEnabled = false
    private var microphoneEnabled = false

    /// Width grows with the two audio buttons so tooltips never clip.
    private let baseHudSize = NSSize(width: 164, height: FloatingControlChrome.height)
    private let audioButtonWidth: CGFloat = 24
    private let audioButtonGap: CGFloat = 2

    private var hudSize: NSSize {
        var width = baseHudSize.width
        width += audioButtonWidth + audioButtonGap
        width += audioButtonWidth + audioButtonGap
        return NSSize(width: width, height: baseHudSize.height)
    }

    init() {
        // hudSize depends on self; compute the equivalent inline before super.init.
        let initialSize = NSSize(
            width: 164 + 2 * (24 + 2),
            height: FloatingControlChrome.height
        )
        super.init(
            contentRect: NSRect(origin: .zero, size: initialSize),
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

    private func microphoneTooltip(enabled: Bool) -> String {
        let base = enabled ? L10n.recordingMicrophoneTooltipOn : L10n.recordingMicrophoneTooltipOff
        return base + " · " + L10n.recordingMicrophoneDeviceMenuHint
    }

    /// Sync the HUD buttons with the audio state the recording launched with.
    func configureAudioButtons(systemAudio: Bool, microphone: Bool) {
        systemAudioEnabled = systemAudio
        microphoneEnabled = microphone
        updateSystemAudioButton()
        updateMicrophoneButton()
    }

    func positionOnScreen(relativeTo screenRect: NSRect, screen: NSScreen?) {
        setFrameOrigin(FloatingControlChrome.origin(
            for: hudSize,
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

        configureGlyphButton(systemAudioButton)
        systemAudioButton.target = self
        systemAudioButton.action = #selector(systemAudioClicked)
        host.addSubview(systemAudioButton)

        configureGlyphButton(microphoneButton)
        microphoneButton.target = self
        microphoneButton.action = #selector(microphoneClicked)
        host.addSubview(microphoneButton)
        microphoneButton.deviceMenuProvider = { [weak self] in
            self?.makeMicrophoneDeviceMenu() ?? NSMenu()
        }
        updateSystemAudioButton()
        updateMicrophoneButton()

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

    /// On/off is carried by the symbol variant (slash when off) and label vs
    /// secondary-label color, not by an accent tint.
    private func updateSystemAudioButton() {
        let on = systemAudioEnabled
        let tooltip = on ? L10n.recordingSystemAudioTooltipOn : L10n.recordingSystemAudioTooltipOff
        systemAudioButton.image = Self.glyph(on ? "speaker.wave.2.fill" : "speaker.slash.fill", tooltip)
        systemAudioButton.contentTintColor = on ? .labelColor : .secondaryLabelColor
        systemAudioButton.toolTip = tooltip
        systemAudioButton.setAccessibilityLabel(tooltip)
    }

    private func updateMicrophoneButton() {
        let on = microphoneEnabled
        let tooltip = microphoneTooltip(enabled: on)
        let label = on ? L10n.recordingMicrophoneTooltipOn : L10n.recordingMicrophoneTooltipOff
        microphoneButton.image = Self.glyph(on ? "mic.fill" : "mic.slash.fill", label)
        microphoneButton.contentTintColor = on ? .labelColor : .secondaryLabelColor
        microphoneButton.toolTip = tooltip
        microphoneButton.setAccessibilityLabel(label)
    }

    private func layoutControls() {
        let buttonSize = FloatingControlChrome.buttonSide
        let height = hudSize.height
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

        let firstAudioX = timeLabel.frame.maxX + 8
        systemAudioButton.frame = NSRect(x: firstAudioX, y: buttonY, width: buttonSize, height: buttonSize)
        microphoneButton.frame = NSRect(x: systemAudioButton.frame.maxX + audioButtonGap, y: buttonY, width: buttonSize, height: buttonSize)

        dragHandle.frame = NSRect(x: hudSize.width - 30, y: (height - 16) / 2, width: 20, height: 16)
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

    @objc private func systemAudioClicked() {
        systemAudioEnabled.toggle()
        updateSystemAudioButton()
        onToggleSystemAudio?(systemAudioEnabled)
    }

    @objc private func microphoneClicked() {
        microphoneEnabled.toggle()
        updateMicrophoneButton()
        onToggleMicrophone?(microphoneEnabled)
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
        menu.addItem(.separator())

        let systemAudio = NSMenuItem(title: L10n.hudMenuSystemAudio, action: #selector(systemAudioClicked), keyEquivalent: "")
        systemAudio.target = self
        systemAudio.state = systemAudioEnabled ? .on : .off
        menu.addItem(systemAudio)
        let microphone = NSMenuItem(title: L10n.hudMenuMicrophone, action: #selector(microphoneClicked), keyEquivalent: "")
        microphone.target = self
        microphone.state = microphoneEnabled ? .on : .off
        menu.addItem(microphone)
        let input = NSMenuItem(title: L10n.hudMenuMicrophoneInput, action: nil, keyEquivalent: "")
        input.submenu = makeMicrophoneDeviceMenu()
        menu.addItem(input)
        return menu
    }

    /// Built fresh on every right-click so hot-plugged devices appear. The
    /// persisted UID is checkmarked; "System Default" has a nil representedObject.
    private func makeMicrophoneDeviceMenu() -> NSMenu {
        let menu = NSMenu()
        let defaultItem = NSMenuItem(
            title: L10n.recordingMicrophoneDeviceDefault,
            action: #selector(microphoneDeviceMenuClicked(_:)),
            keyEquivalent: ""
        )
        defaultItem.target = self
        menu.addItem(defaultItem)
        menu.addItem(.separator())
        for device in AudioInputDevices.available() {
            let item = NSMenuItem(
                title: device.name,
                action: #selector(microphoneDeviceMenuClicked(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = device.uid
            menu.addItem(item)
        }
        let currentUID = Defaults.recordingMicrophoneDeviceUID
        for item in menu.items {
            item.state = ((item.representedObject as? String) == currentUID) ? .on : .off
        }
        return menu
    }

    @objc private func microphoneDeviceMenuClicked(_ sender: NSMenuItem) {
        onSelectMicrophoneDevice?(sender.representedObject as? String)
    }
}

/// Left-click toggles the mic; right-click pops the input-device picker.
private final class AudioDeviceMenuButton: NSButton {
    var deviceMenuProvider: (() -> NSMenu)?

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = deviceMenuProvider?() else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.height), in: self)
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
