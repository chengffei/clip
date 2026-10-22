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
    private let stopButton = NSButton()
    private let pauseButton = NSButton()
    private let recordDot = NSTextField(labelWithString: "●")
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
        containerView.wantsLayer = true
        containerView.layer?.cornerRadius = FloatingControlChrome.cornerRadius
        containerView.layer?.borderWidth = FloatingControlChrome.borderWidth
        containerView.applyAppearance()
        contentView = containerView

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
        recordDot.textColor = paused ? .systemOrange : .systemRed
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
        updateAudioButtonAppearance(systemAudioButton, enabled: systemAudio, onTooltip: L10n.recordingSystemAudioTooltipOn, offTooltip: L10n.recordingSystemAudioTooltipOff)
        updateAudioButtonAppearance(microphoneButton, enabled: microphone, onTooltip: microphoneTooltip(enabled: true), offTooltip: microphoneTooltip(enabled: false))
    }

    func positionOnScreen(relativeTo screenRect: NSRect, screen: NSScreen?) {
        setFrameOrigin(FloatingControlChrome.origin(
            for: hudSize,
            relativeTo: screenRect,
            visibleFrame: screen?.visibleFrame
        ))
    }

    private func setupControls() {
        stopButton.bezelStyle = .regularSquare
        stopButton.isBordered = false
        stopButton.imageScaling = .scaleProportionallyDown
        stopButton.image = NSImage(systemSymbolName: "stop.fill", accessibilityDescription: L10n.recordingStop)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold))
        stopButton.contentTintColor = .labelColor
        stopButton.toolTip = L10n.recordingStop
        stopButton.target = self
        stopButton.action = #selector(stopClicked)
        containerView.addSubview(stopButton)

        pauseButton.bezelStyle = .regularSquare
        pauseButton.isBordered = false
        pauseButton.imageScaling = .scaleProportionallyDown
        pauseButton.contentTintColor = .labelColor
        pauseButton.target = self
        pauseButton.action = #selector(pauseClicked)
        containerView.addSubview(pauseButton)
        updatePauseIcon()

        recordDot.font = .systemFont(ofSize: 11, weight: .bold)
        recordDot.textColor = .systemRed
        recordDot.isBezeled = false
        recordDot.drawsBackground = false
        recordDot.isEditable = false
        containerView.addSubview(recordDot)

        timeLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        timeLabel.textColor = .labelColor
        timeLabel.isBezeled = false
        timeLabel.drawsBackground = false
        timeLabel.isEditable = false
        containerView.addSubview(timeLabel)

        setupAudioButton(
            systemAudioButton,
            symbol: "speaker.wave.2.fill",
            action: #selector(systemAudioClicked)
        )
        setupAudioButton(
            microphoneButton,
            symbol: "mic.fill",
            action: #selector(microphoneClicked)
        )
        microphoneButton.deviceMenuProvider = { [weak self] in
            self?.makeMicrophoneDeviceMenu() ?? NSMenu()
        }

        dragHandle.image = NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 10, weight: .medium))
        dragHandle.contentTintColor = .secondaryLabelColor
        dragHandle.imageScaling = .scaleProportionallyDown
        containerView.addSubview(dragHandle)
    }

    private func setupAudioButton(_ button: NSButton, symbol: String, action: Selector) {
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.imageScaling = .scaleProportionallyDown
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold))
        button.contentTintColor = .tertiaryLabelColor
        button.target = self
        button.action = action
        containerView.addSubview(button)
    }

    private func updateAudioButtonAppearance(
        _ button: NSButton,
        enabled: Bool,
        onTooltip: String,
        offTooltip: String
    ) {
        button.contentTintColor = enabled ? .systemBlue : .tertiaryLabelColor
        button.toolTip = enabled ? onTooltip : offTooltip
        button.alphaValue = enabled ? 1.0 : 0.55   // dim when off
    }

    private func layoutControls() {
        let buttonSize = FloatingControlChrome.buttonSide
        let padding: CGFloat = 6
        let height = hudSize.height

        stopButton.frame = NSRect(x: padding, y: (height - buttonSize) / 2, width: buttonSize, height: buttonSize)
        pauseButton.frame = NSRect(x: stopButton.frame.maxX + 2, y: (height - buttonSize) / 2, width: buttonSize, height: buttonSize)

        recordDot.sizeToFit()
        timeLabel.sizeToFit()
        recordDot.frame.origin = NSPoint(x: pauseButton.frame.maxX + 6, y: (height - recordDot.frame.height) / 2)
        timeLabel.frame.origin = NSPoint(x: recordDot.frame.maxX + 3, y: (height - timeLabel.frame.height) / 2)

        let firstAudioX = timeLabel.frame.maxX + 8
        systemAudioButton.frame = NSRect(x: firstAudioX, y: (height - buttonSize) / 2, width: buttonSize, height: buttonSize)
        microphoneButton.frame = NSRect(x: systemAudioButton.frame.maxX + audioButtonGap, y: (height - buttonSize) / 2, width: buttonSize, height: buttonSize)

        dragHandle.frame = NSRect(x: hudSize.width - 26, y: (height - 16) / 2, width: 20, height: 16)
    }

    private func updatePauseIcon() {
        let symbol = isPaused ? "play.fill" : "pause.fill"
        pauseButton.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold))
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
        updateAudioButtonAppearance(
            systemAudioButton,
            enabled: systemAudioEnabled,
            onTooltip: L10n.recordingSystemAudioTooltipOn,
            offTooltip: L10n.recordingSystemAudioTooltipOff
        )
        onToggleSystemAudio?(systemAudioEnabled)
    }

    @objc private func microphoneClicked() {
        microphoneEnabled.toggle()
        updateAudioButtonAppearance(
            microphoneButton,
            enabled: microphoneEnabled,
            onTooltip: microphoneTooltip(enabled: true),
            offTooltip: microphoneTooltip(enabled: false)
        )
        onToggleMicrophone?(microphoneEnabled)
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

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyAppearance()
    }

    func applyAppearance() {
        layer?.backgroundColor = AdaptiveChrome.resolvedCGColor(
            AdaptiveChrome.floatingBackground,
            for: effectiveAppearance
        )
        layer?.borderColor = AdaptiveChrome.resolvedCGColor(
            AdaptiveChrome.border,
            for: effectiveAppearance
        )
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
