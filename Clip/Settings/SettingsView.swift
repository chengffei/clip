import AppKit
import Carbon
import PermissionFlow

// MARK: - Tab model

enum SettingsTab: String, CaseIterable {
    case general
    case shortcuts
    case toolbar
    case capture
    case recording
    case files
    case ocr
    case permissions
    case about

    var title: String {
        switch self {
        case .general: return L10n.settingsTabGeneral
        case .shortcuts: return L10n.settingsTabShortcuts
        case .toolbar: return L10n.settingsTabToolbar
        case .capture: return L10n.settingsGeneralCapture
        case .recording: return L10n.settingsGeneralRecording
        case .files: return L10n.settingsGeneralFiles
        case .ocr: return L10n.settingsTabOCR
        case .permissions: return L10n.settingsTabPermissions
        case .about: return L10n.settingsTabAbout
        }
    }

    var iconName: String {
        switch self {
        case .general: return "gearshape.fill"
        case .shortcuts: return "keyboard"
        case .toolbar: return "slider.horizontal.3"
        case .capture: return "crop"
        case .recording: return "record.circle"
        case .files: return "doc"
        case .ocr: return "text.viewfinder"
        case .permissions: return "lock.shield.fill"
        case .about: return "info.circle.fill"
        }
    }

    var iconTint: NSColor {
        switch self {
        case .general: return Brand.accent
        case .shortcuts, .capture, .toolbar:
            return Brand.accent
        case .recording:
            return Brand.accent
        case .files, .ocr:
            return Brand.accent
        case .permissions: return Brand.accent
        case .about:
            return Brand.accent
        }
    }
}

private enum HistoryPanelSettingsMode {
    case dialog
    case notch
}

class SettingsView: NSView {

    var isStartup: Bool = false
    var onMenuBarToggle: ((Bool) -> Void)?
    var onLaunch: (() -> Void)?

    // Switches
    private var menuBarSwitch: NSSwitch!
    private var launchAtLoginSwitch: NSSwitch!
    private var pinAcrossSpacesSwitch: NSSwitch!

    // Picker & slider
    private var langPicker: NSPopUpButton!
    private var historyCacheSwitch: NSSwitch!
    private var clipboardTextCacheSwitch: NSSwitch!

    private var historyCacheSlider: SettingsTickSlider!
    private var historyCacheValueLabel: NSTextField!
    private var clipboardTextHistoryLimitSlider: SettingsTickSlider!
    private var clipboardTextHistoryLimitValueLabel: NSTextField!
    private var historyPanelModePreview: HistoryPanelModePreviewView!
    private var historyPanelDialogOption: HistoryPanelModeOptionView!
    private var historyPanelNotchOption: HistoryPanelModeOptionView!
    private var historyNotchTriggerLabel: NSTextField?
    private var historyNotchTriggerPopup: NSPopUpButton?
    private var countdownSlider: SettingsTickSlider!
    private var countdownValueLabel: NSTextField!
    private var countdownTitleLabel: NSTextField!
    private var countdownHintLabel: NSTextField!

    // Window-capture shadow card
    private var windowShadowSwitch: NSSwitch!
    private var windowShadowSlider: NSSlider!
    private var windowShadowSizeValueLabel: NSTextField!
    private var windowShadowPreview: ShadowPreviewView!
    private var windowShadowTitleLabel: NSTextField!
    private var windowShadowSubtitleLabel: NSTextField?
    private var windowShadowSizeTitleLabel: NSTextField!
    private var windowShadowSizeHintLabel: NSTextField!

    // Screenshot shortcut card
    private var shortcutTitleLabel: NSTextField!
    private var shortcutField: NSTextField!
    private var shortcutSetButton: NSButton!
    private var shortcutRestoreButton: NSButton!
    private var shortcutRecordingMonitor: Any?

    // Full-screen screenshot shortcut card
    private var fullScreenScreenshotShortcutTitleLabel: NSTextField!
    private var fullScreenScreenshotShortcutField: NSTextField!
    private var fullScreenScreenshotShortcutSetButton: NSButton!
    private var fullScreenScreenshotShortcutRestoreButton: NSButton!
    private var fullScreenScreenshotShortcutRecordingMonitor: Any?

    // Color picker shortcut card
    private var colorPickerShortcutTitleLabel: NSTextField!
    private var colorPickerShortcutField: NSTextField!
    private var colorPickerShortcutSetButton: NSButton!
    private var colorPickerShortcutRestoreButton: NSButton!
    private var colorPickerShortcutRecordingMonitor: Any?

    // Quick Pin shortcut card
    private var quickPinShortcutTitleLabel: NSTextField!
    private var quickPinShortcutField: NSTextField!
    private var quickPinShortcutSetButton: NSButton!
    private var quickPinShortcutRestoreButton: NSButton!
    private var quickPinShortcutRecordingMonitor: Any?

    // Pin selected image shortcut card

    // Pin clipboard image shortcut card

    // Pin clipboard text shortcut card

    // Edit selected image shortcut card

    // Edit clipboard image shortcut card

    // Text recognition shortcut card
    private var textRecognitionShortcutTitleLabel: NSTextField!
    private var textRecognitionShortcutField: NSTextField!
    private var textRecognitionShortcutSetButton: NSButton!
    private var textRecognitionShortcutRestoreButton: NSButton!
    private var textRecognitionShortcutRecordingMonitor: Any?

    // Copy image text shortcut card
    private var copyImageTextShortcutTitleLabel: NSTextField!
    private var copyImageTextShortcutField: NSTextField!
    private var copyImageTextShortcutSetButton: NSButton!
    private var copyImageTextShortcutRestoreButton: NSButton!
    private var copyImageTextShortcutRecordingMonitor: Any?

    // Screenshot translation shortcut card

    // Recording shortcut card
    private var recordShortcutTitleLabel: NSTextField!
    private var recordShortcutField: NSTextField!
    private var recordShortcutSetButton: NSButton!
    private var recordShortcutRestoreButton: NSButton!
    private var recordShortcutRecordingMonitor: Any?

    // Image Merge shortcut card

    // File upload shortcut card

    // Copy-to-clipboard (editor confirm) shortcut card
    private var clipboardShortcutTitleLabel: NSTextField!
    private var clipboardShortcutField: NSTextField!
    private var clipboardShortcutSetButton: NSButton!
    private var clipboardShortcutRestoreButton: NSButton!
    private var clipboardShortcutRecordingMonitor: Any?

    // Save-to-file shortcut card (default ⌘S)
    private var fileSaveShortcutTitleLabel: NSTextField!
    private var fileSaveShortcutField: NSTextField!
    private var fileSaveShortcutSetButton: NSButton!
    private var fileSaveShortcutRestoreButton: NSButton!
    private var fileSaveShortcutRecordingMonitor: Any?

    // History navigation shortcut cards



    private var shortcutResetButton: NSButton?

    // Permission badges
    private var accessibilityBadge: StatusBadge!
    private var screenRecordingBadge: StatusBadge!
    private var microphoneBadge: StatusBadge?

    // Sidebar bottom action — Launch App in startup mode, Quit App otherwise.
    private var launchButton: ActionButton?

    // Labels (kept for language switching)
    private var menuBarTitleLabel: NSTextField!
    private var launchAtLoginTitleLabel: NSTextField!
    private var pinAcrossSpacesTitleLabel: NSTextField!
    private var pinAcrossSpacesSubtitleLabel: NSTextField!
    private var langTitleLabel: NSTextField!
    private var historyCacheToggleTitleLabel: NSTextField!
    private var historyCacheToggleHintLabel: NSTextField?
    private var clipboardTextCacheToggleTitleLabel: NSTextField!
    private var clipboardTextCacheToggleHintLabel: NSTextField?
    private var clipboardTextHistoryLimitTitleLabel: NSTextField!
    private var historyCacheTitleLabel: NSTextField!
    private var historyPanelDisplayModeTitleLabel: NSTextField!
    private var historyPanelDisplayModeHintLabel: NSTextField!
    private var historyPanelDialogModeTitleLabel: NSTextField!
    private var historyPanelDialogModeHintLabel: NSTextField?
    private var historyPanelNotchModeTitleLabel: NSTextField!
    private var historyPanelNotchModeHintLabel: NSTextField?
    private var permHeaderSubtitleLabel: NSTextField?
    private var accessibilityNameLabel: NSTextField!
    private var accessibilityDescLabel: NSTextField!
    private var screenRecordingNameLabel: NSTextField!
    private var screenRecordingDescLabel: NSTextField!
    private var microphoneNameLabel: NSTextField?
    private var microphoneDescLabel: NSTextField?
    private var aboutTaglineLabel: NSTextField?
    private var aboutLicenseTitleLabel: NSTextField?
    private var aboutSourceTitleLabel: NSTextField?
    private var aboutStarTitleLabel: NSTextField?
    private var aboutFeatureRequestTitleLabel: NSTextField?
    private var aboutBugReportTitleLabel: NSTextField?

    // Error log card (About pane) — expandable macOS crash report viewer.

    // Sidebar / detail chrome
    private var selectedTab: SettingsTab = .general
    private var tabButtons: [TabButton] = []
    private var detailTitleLabel: NSTextField!
    private var detailScrollView: NSScrollView!
    private var historyNotchTriggerRow: NSView?

    private var paneContainer: NSView!
    private var paneViews: [SettingsTab: NSView] = [:]
    private var filenameRuleCard: FilenameRuleCard?
    private var toolbarPane: ToolbarSettingsPane?
    private var sectionCaptions: [SidebarSectionCaption] = []
    private var screenshotQualityTitleLabel: NSTextField!
    private var screenshotQualitySubtitleLabel: NSTextField!
    private var screenshotQualitySaveTitleLabel: NSTextField!
    private var screenshotQualitySaveHintLabel: NSTextField!
    private var screenshotQualitySavePopup: NSPopUpButton!
    private var screenshotQualityClipboardTitleLabel: NSTextField!
    private var screenshotQualityClipboardHintLabel: NSTextField!
    private var screenshotQualityClipboardPopup: NSPopUpButton!
    private var savePathTitleLabel: NSTextField!
    private var savePathSubtitleLabel: NSTextField!
    private var askSaveLocationTitleLabel: NSTextField!
    private var askSaveLocationHintLabel: NSTextField?
    private var askSaveLocationSwitch: NSSwitch!
    private var autoRevealSavedFilesTitleLabel: NSTextField!
    private var autoRevealSavedFilesHintLabel: NSTextField?
    private var autoRevealSavedFilesSwitch: NSSwitch!
    private var recordingSavePathTitleLabel: NSTextField!
    private var recordingSavePathValueLabel: NSTextField!
    private var recordingSavePathChooseButton: NSButton!
    private var recordingSavePathRevealButton: NSButton!
    private var recordingSaveFormatTitleLabel: NSTextField!
    private var recordingSaveFormatPopup: NSPopUpButton!
    private var recordingSystemAudioTitleLabel: NSTextField?
    private var recordingSystemAudioHintLabel: NSTextField?
    private var recordingSystemAudioSwitch: NSSwitch?
    private var recordingMicrophoneTitleLabel: NSTextField?
    private var recordingMicrophoneHintLabel: NSTextField?
    private var recordingMicrophoneSwitch: NSSwitch?
    private var recordingMicrophoneDeviceTitleLabel: NSTextField?
    private var recordingMicrophoneDevicePopup: NSPopUpButton?
    private var screenshotSavePathTitleLabel: NSTextField!
    private var screenshotSavePathValueLabel: NSTextField!
    private var screenshotSavePathChooseButton: NSButton!
    private var screenshotSavePathRevealButton: NSButton!

    private var refreshTimer: Timer?
    private var gradientLayer: CAGradientLayer?
    private lazy var permissionFlowController = PermissionFlow.makeController(
        configuration: PermissionFlowConfiguration(
            requiredAppURLs: [Bundle.main.bundleURL],
            localeIdentifier: Defaults.language.lprojName
        )
    )

    init(frame: NSRect, isStartup: Bool = false) {
        self.isStartup = isStartup
        super.init(frame: frame)
        appearance = NSAppearance(named: .aqua)
        wantsLayer = true
        setupBackground()
        setupUI()
        startRefreshTimer()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateLocalization),
            name: .languageDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        refreshTimer?.invalidate()
        cancelShortcutRecording()
        cancelFullScreenScreenshotShortcutRecording()
        cancelColorPickerShortcutRecording()
        cancelQuickPinShortcutRecording()
        cancelTextRecognitionShortcutRecording()
        cancelCopyImageTextShortcutRecording()
        cancelRecordShortcutRecording()
        cancelClipboardShortcutRecording()
        cancelFileSaveShortcutRecording()
        NotificationCenter.default.removeObserver(self)
    }

    override func layout() {
        super.layout()
        gradientLayer?.frame = bounds
    }

    override var acceptsFirstResponder: Bool { true }

    // MARK: - Background

    private func setupBackground() {
        let gradient = CAGradientLayer()
        gradient.colors = [
            Brand.sidebar.cgColor,
            Brand.sidebar.cgColor,
        ]
        gradient.startPoint = CGPoint(x: 0, y: 1)
        gradient.endPoint = CGPoint(x: 1, y: 0)
        layer?.addSublayer(gradient)
        gradientLayer = gradient
    }

    // MARK: - Layout

    private func setupUI() {
        let sidebar = buildSidebar()
        addSubview(sidebar)

        let detail = buildDetailPanel()
        addSubview(detail)

        NSLayoutConstraint.activate([
            sidebar.topAnchor.constraint(equalTo: topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: bottomAnchor),
            sidebar.leadingAnchor.constraint(equalTo: leadingAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 212),

            detail.topAnchor.constraint(equalTo: topAnchor),
            detail.bottomAnchor.constraint(equalTo: bottomAnchor),
            detail.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            detail.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        // Build all panes
        buildCapturePreferencePanes()
        paneViews[.shortcuts] = buildShortcutsPane()
        paneViews[.toolbar] = buildToolbarPane()
        paneViews[.ocr] = OCRSettingsPane()
        paneViews[.permissions] = buildPermissionsPane()
        paneViews[.about] = buildAboutPane()

        // Default selection
        let initial: SettingsTab = isStartup ? .permissions : .general
        selectTab(initial)

        updateLaunchButtonVisibility()
        refreshPermissionStatus()
        refreshShortcutDisplay()
        refreshFullScreenScreenshotShortcutDisplay()
        refreshColorPickerShortcutDisplay()
        refreshQuickPinShortcutDisplay()
        refreshTextRecognitionShortcutDisplay()
        refreshCopyImageTextShortcutDisplay()
        refreshRecordShortcutDisplay()
        refreshClipboardShortcutDisplay()
        refreshFileSaveShortcutDisplay()
    }

    // MARK: - Sidebar

    private func buildSidebar() -> NSView {
        let panel = SidebarPanel()
        panel.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        let navigation = NSScrollView()
        navigation.translatesAutoresizingMaskIntoConstraints = false
        navigation.drawsBackground = false
        navigation.hasVerticalScroller = false
        navigation.verticalScroller = nil
        navigation.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sidebarBoundsDidChange),
            name: NSView.boundsDidChangeNotification,
            object: navigation.contentView
        )
        panel.addSubview(navigation)
        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        navigation.documentView = document
        document.addSubview(stack)
        NSLayoutConstraint.activate([
            document.topAnchor.constraint(equalTo: navigation.contentView.topAnchor),
            document.leadingAnchor.constraint(equalTo: navigation.contentView.leadingAnchor),
            document.widthAnchor.constraint(equalTo: navigation.contentView.widthAnchor),
            stack.topAnchor.constraint(equalTo: document.topAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor),
        ])

        for tab in SettingsTab.allCases {
            if tab == .capture || tab == .ocr {
                let caption = SidebarSectionCaption(
                    text: tab == .capture ? L10n.settingsSectionCapture : L10n.settingsSectionSystem
                )
                sectionCaptions.append(caption)
                stack.addArrangedSubview(caption)
                caption.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            }
            let btn = TabButton(tab: tab)
            btn.target = self
            btn.action = #selector(tabClicked(_:))
            btn.translatesAutoresizingMaskIntoConstraints = false
            tabButtons.append(btn)
            stack.addArrangedSubview(btn)
            btn.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        let divider = NSView()
        divider.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(divider)

        let bottomBtn = ActionButton(symbolName: "power", title: L10n.launchApp, tint: Brand.accent)
        bottomBtn.target = self
        bottomBtn.action = #selector(launchClicked)
        bottomBtn.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(bottomBtn)
        launchButton = bottomBtn

        NSLayoutConstraint.activate([
            navigation.topAnchor.constraint(equalTo: panel.topAnchor, constant: 52),
            navigation.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 12),
            navigation.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -12),
            navigation.bottomAnchor.constraint(equalTo: divider.topAnchor, constant: -8),

            divider.heightAnchor.constraint(equalToConstant: 1),
            divider.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 12),
            divider.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -12),
            divider.bottomAnchor.constraint(equalTo: bottomBtn.topAnchor, constant: -8),

            bottomBtn.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 12),
            bottomBtn.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -12),
            bottomBtn.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -12),
        ])

        return panel
    }

    @objc private func sidebarBoundsDidChange() {
        for button in tabButtons {
            button.refreshHoverAtCurrentMouseLocation()
        }
    }

    private func appVersionString() -> String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        return "v\(short)"
    }

    private func makeBuildConfigurationBadge() -> NSView {
        #if DEBUG
        let title = "DEBUG"
        let color = NSColor.systemOrange
        #else
        let title = "RELEASE"
        let color = NSColor.systemGreen
        #endif

        let badge = NSView()
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 4
        badge.layer?.cornerCurve = .continuous
        badge.layer?.backgroundColor = color.withAlphaComponent(0.18).cgColor
        badge.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 9, weight: .semibold)
        label.textColor = color
        label.translatesAutoresizingMaskIntoConstraints = false
        badge.addSubview(label)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: badge.topAnchor, constant: 2),
            label.bottomAnchor.constraint(equalTo: badge.bottomAnchor, constant: -2),
            label.leadingAnchor.constraint(equalTo: badge.leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: badge.trailingAnchor, constant: -6),
        ])
        badge.setContentHuggingPriority(.required, for: .horizontal)
        badge.setContentCompressionResistancePriority(.required, for: .horizontal)
        return badge
    }

    @objc private func tabClicked(_ sender: TabButton) {
        selectTab(sender.tab)
    }

    func selectTab(_ tab: SettingsTab) {
        if selectedTab == .toolbar && tab != .toolbar {
            toolbarPane?.cancelShortcutRecording()
        }
        window?.makeFirstResponder(nil)
        selectedTab = tab
        for btn in tabButtons {
            btn.isSelected = (btn.tab == tab)
        }
        detailTitleLabel?.stringValue = tab.title

        // Rebuild the mic device list on every visit so hot-plugs appear.
        if tab == .recording {
            refreshMicrophoneDevicePopup()
        }

        // Swap pane content
        guard let pane = paneViews[tab] else { return }
        for sub in paneContainer.subviews { sub.removeFromSuperview() }
        pane.translatesAutoresizingMaskIntoConstraints = false
        paneContainer.addSubview(pane)
        NSLayoutConstraint.activate([
            pane.topAnchor.constraint(equalTo: paneContainer.topAnchor),
            pane.leadingAnchor.constraint(equalTo: paneContainer.leadingAnchor),
            pane.trailingAnchor.constraint(equalTo: paneContainer.trailingAnchor),
            pane.bottomAnchor.constraint(equalTo: paneContainer.bottomAnchor),
        ])
        layoutSubtreeIfNeeded()
        detailScrollView.contentView.scroll(to: .zero)
        detailScrollView.reflectScrolledClipView(detailScrollView.contentView)
    }

    // MARK: - Detail panel

    private func buildDetailPanel() -> NSView {
        let panel = DetailPanel()
        panel.translatesAutoresizingMaskIntoConstraints = false

        // Title
        let title = NSTextField(labelWithString: SettingsTab.general.title)
        title.font = NSFont.systemFont(ofSize: 22, weight: .semibold)
        title.textColor = Brand.text
        title.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(title)
        detailTitleLabel = title

        // Scroll view fills the rest of the panel — the launch / quit action
        // lives in the sidebar bottom now, freeing the right-pane footer.
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.verticalScrollElasticity = .allowed
        panel.addSubview(scroll)
        detailScrollView = scroll

        let container = FlippedView()
        container.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = container
        paneContainer = container

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 12),
            title.topAnchor.constraint(equalTo: panel.topAnchor, constant: 26),
            title.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 28),
            title.trailingAnchor.constraint(lessThanOrEqualTo: panel.trailingAnchor, constant: -28),

            scroll.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: panel.bottomAnchor),

            container.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            container.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            container.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
        ])

        return panel
    }

    // MARK: - Pane builders

    private func buildCapturePreferencePanes() {
        let basic = paneStack()
        let capture = paneStack()
        let recording = paneStack()
        let history = paneStack()
        let files = paneStack()

        let togglesCard = CardView()
        let togglesInner = verticalInnerStack()
        togglesCard.addSubview(togglesInner)
        pin(togglesInner, to: togglesCard, insets: NSEdgeInsets(top: 14, left: 14, bottom: 6, right: 14))
        let langRow = NSStackView()
        langRow.orientation = .horizontal
        langRow.alignment = .centerY
        langRow.spacing = 10
        langRow.translatesAutoresizingMaskIntoConstraints = false

        langTitleLabel = primaryLabel(L10n.languageHeader)
        langRow.addArrangedSubview(langTitleLabel)
        langRow.addArrangedSubview(flexSpacer())

        langPicker = NSPopUpButton(frame: .zero, pullsDown: false)
        langPicker.addItems(withTitles: AppLanguage.allCases.map { $0.displayName })
        langPicker.selectItem(at: AppLanguage.allCases.firstIndex(of: Defaults.language) ?? 0)
        langPicker.target = self
        langPicker.action = #selector(languageChanged(_:))
        langPicker.controlSize = .small
        langPicker.font = NSFont.systemFont(ofSize: 12)
        langRow.addArrangedSubview(langPicker)

        togglesInner.addArrangedSubview(langRow)
        langRow.widthAnchor.constraint(equalTo: togglesInner.widthAnchor).isActive = true
        togglesInner.setCustomSpacing(14, after: langRow)
        togglesInner.addArrangedSubview(rowDivider())
        let menuBar = makeToggleRow(
            title: L10n.showMenuBarIcon,
            subtitle: nil,
            isOn: Defaults.showMenuBar,
            action: #selector(menuBarSwitchToggled(_:))
        )
        menuBarTitleLabel = menuBar.title
        menuBarSwitch = menuBar.toggle
        togglesInner.addArrangedSubview(menuBar.row)
        menuBar.row.widthAnchor.constraint(equalTo: togglesInner.widthAnchor).isActive = true
        togglesInner.addArrangedSubview(rowDivider())

        let login = makeToggleRow(
            title: L10n.launchAtLogin,
            subtitle: nil,
            isOn: LaunchAtLogin.isEnabled,
            action: #selector(launchAtLoginToggled(_:))
        )
        launchAtLoginTitleLabel = login.title
        launchAtLoginSwitch = login.toggle
        togglesInner.addArrangedSubview(login.row)
        login.row.widthAnchor.constraint(equalTo: togglesInner.widthAnchor).isActive = true

        basic.addArrangedSubview(togglesCard)
        togglesCard.widthAnchor.constraint(equalTo: basic.widthAnchor).isActive = true

        buildWindowShadowCard(into: capture)
        let pinCard = CardView()
        let pinInner = verticalInnerStack()
        pinCard.addSubview(pinInner)
        pin(pinInner, to: pinCard, insets: NSEdgeInsets(top: 6, left: 14, bottom: 6, right: 14))
        let pinAcrossSpaces = makeToggleRow(
            title: L10n.pinAcrossSpaces,
            subtitle: L10n.pinAcrossSpacesHint,
            isOn: Defaults.pinAcrossSpaces,
            action: #selector(pinAcrossSpacesToggled(_:))
        )
        pinAcrossSpacesTitleLabel = pinAcrossSpaces.title
        pinAcrossSpacesSubtitleLabel = pinAcrossSpaces.subtitle
        pinAcrossSpacesSwitch = pinAcrossSpaces.toggle
        pinInner.addArrangedSubview(pinAcrossSpaces.row)
        pinAcrossSpaces.row.widthAnchor.constraint(equalTo: pinInner.widthAnchor).isActive = true

        capture.addArrangedSubview(pinCard)
        pinCard.widthAnchor.constraint(equalTo: capture.widthAnchor).isActive = true

        buildRecordingCard(into: recording)
        buildSavePathCard(into: files)
        buildScreenshotQualityCard(into: files)
        let filenameCard = FilenameRuleCard()
        filenameRuleCard = filenameCard
        files.addArrangedSubview(filenameCard)
        filenameCard.widthAnchor.constraint(equalTo: files.widthAnchor).isActive = true

        paneViews[.general] = wrapPane(basic)
        paneViews[.capture] = wrapPane(capture)
        paneViews[.recording] = wrapPane(recording)
        paneViews[.files] = wrapPane(files)
    }

    /// Window-capture shadow card: a toggle for the rounded-corner + drop
    /// shadow effect, a size slider, and a live preview of the result.
    private func buildWindowShadowCard(into stack: NSStackView) {
        let card = CardView()
        let inner = NSStackView()
        inner.orientation = .vertical
        inner.alignment = .leading
        inner.spacing = 10
        inner.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(inner)
        pin(inner, to: card, insets: NSEdgeInsets(top: 4, left: 14, bottom: 14, right: 14))

        // Enable toggle
        let toggle = makeToggleRow(
            title: L10n.windowShadowToggleLabel,
            subtitle: L10n.windowShadowToggleHint,
            isOn: Defaults.windowShadowEnabled,
            action: #selector(windowShadowToggled(_:))
        )
        windowShadowTitleLabel = toggle.title
        windowShadowSubtitleLabel = toggle.subtitle
        windowShadowSwitch = toggle.toggle
        inner.addArrangedSubview(toggle.row)
        toggle.row.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true

        let divider = rowDivider()
        inner.addArrangedSubview(divider)
        divider.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true

        // Size header — title + numeric value
        let header = NSStackView()
        header.orientation = .horizontal
        header.alignment = .firstBaseline
        header.spacing = 8
        header.translatesAutoresizingMaskIntoConstraints = false

        windowShadowSizeTitleLabel = primaryLabel(L10n.shadowSizeLabel)
        header.addArrangedSubview(windowShadowSizeTitleLabel)
        header.addArrangedSubview(flexSpacer())

        windowShadowSizeValueLabel = NSTextField(labelWithString: "\(Int(Defaults.windowShadowSize.rounded()))")
        windowShadowSizeValueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        windowShadowSizeValueLabel.textColor = Brand.text.withAlphaComponent(0.88)
        header.addArrangedSubview(windowShadowSizeValueLabel)

        inner.addArrangedSubview(header)
        header.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true

        // Size slider
        let slider = NSSlider(
            value: Defaults.windowShadowSize,
            minValue: Defaults.windowShadowSizeMin,
            maxValue: Defaults.windowShadowSizeMax,
            target: self,
            action: #selector(windowShadowSizeChanged(_:))
        )
        slider.controlSize = .small
        slider.isContinuous = true
        slider.translatesAutoresizingMaskIntoConstraints = false
        windowShadowSlider = slider
        inner.addArrangedSubview(slider)
        slider.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true

        // Live preview
        let preview = ShadowPreviewView()
        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.shadowSize = CGFloat(Defaults.windowShadowSize)
        windowShadowPreview = preview
        inner.addArrangedSubview(preview)
        preview.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true
        preview.heightAnchor.constraint(equalToConstant: 120).isActive = true

        windowShadowSizeHintLabel = secondaryLabel(L10n.windowShadowSizeHint, wrapping: true)
        inner.addArrangedSubview(windowShadowSizeHintLabel)
        windowShadowSizeHintLabel.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true

        updateWindowShadowControlsEnabled()

        stack.addArrangedSubview(card)
        card.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    /// Dim and disable the size controls when the shadow toggle is off.
    private func updateWindowShadowControlsEnabled() {
        let on = Defaults.windowShadowEnabled
        windowShadowSlider?.isEnabled = on
        windowShadowSizeTitleLabel?.textColor = Brand.text.withAlphaComponent(on ? 0.94 : 0.4)
        windowShadowSizeValueLabel?.textColor = Brand.text.withAlphaComponent(on ? 0.88 : 0.4)
        windowShadowPreview?.isEffectEnabled = on
    }

    private func selectedHistoryPanelMode() -> HistoryPanelSettingsMode {
        Defaults.historyPanelNotchEnabled ? .notch : .dialog
    }

    private func refreshSavePathControls() {
        recordingSavePathValueLabel?.stringValue = SaveDestination.displayPath(Defaults.recordingSaveDirectory)
        screenshotSavePathValueLabel?.stringValue = SaveDestination.displayPath(Defaults.screenshotSaveDirectory)
        recordingSavePathValueLabel?.toolTip = Defaults.recordingSaveDirectory.path
        screenshotSavePathValueLabel?.toolTip = Defaults.screenshotSaveDirectory.path
        refreshRecordingSaveFormatPopup()
    }

    private func refreshScreenshotQualityControls() {
        refreshScreenshotQualityPopup(screenshotQualitySavePopup, selected: Defaults.screenshotSaveQuality)
        refreshScreenshotQualityPopup(screenshotQualityClipboardPopup, selected: Defaults.screenshotClipboardQuality)
        screenshotQualitySaveHintLabel?.stringValue = Defaults.screenshotSaveQuality.localizedHint
        screenshotQualitySavePopup?.toolTip = Defaults.screenshotSaveQuality.localizedHint
        screenshotQualityClipboardHintLabel?.stringValue = Defaults.screenshotClipboardQuality.localizedHint
        screenshotQualityClipboardPopup?.toolTip = Defaults.screenshotClipboardQuality.localizedHint
    }

    private func refreshScreenshotQualityPopup(
        _ popup: NSPopUpButton?,
        selected: ScreenshotImageQuality
    ) {
        guard let popup else { return }
        popup.removeAllItems()
        for quality in ScreenshotImageQuality.allCases {
            popup.addItem(withTitle: quality.localizedTitle)
            popup.lastItem?.representedObject = quality.rawValue
        }
        if let index = ScreenshotImageQuality.allCases.firstIndex(of: selected) {
            popup.selectItem(at: index)
        }
    }

    private func refreshRecordingSaveFormatPopup() {
        guard let popup = recordingSaveFormatPopup else { return }
        let selected = Defaults.recordingSavePreference
        popup.removeAllItems()
        for preference in RecordingSavePreference.allCases {
            popup.addItem(withTitle: preference.displayName)
            popup.lastItem?.representedObject = preference.rawValue
        }
        if let index = RecordingSavePreference.allCases.firstIndex(of: selected) {
            popup.selectItem(at: index)
        }
    }

    /// Rebuild the mic device popup from the live CoreAudio list; falls back
    /// to "System Default" when the persisted UID is unplugged.
    private func refreshMicrophoneDevicePopup() {
        guard let popup = recordingMicrophoneDevicePopup else { return }
        let selectedUID = Defaults.recordingMicrophoneDeviceUID
        popup.removeAllItems()
        popup.addItem(withTitle: L10n.recordingMicrophoneDeviceDefault)
        popup.lastItem?.representedObject = nil
        for device in AudioInputDevices.available() {
            popup.addItem(withTitle: device.name)
            popup.lastItem?.representedObject = device.uid
        }
        if let selectedUID,
           let index = (0..<popup.numberOfItems).first(where: {
               popup.item(at: $0)?.representedObject as? String == selectedUID
           }) {
            popup.selectItem(at: index)
        } else {
            popup.selectItem(at: 0)
        }
    }

    private func updateMicrophoneControlsEnabled() {
        let enabled = Defaults.recordingMicrophoneEnabled
        recordingMicrophoneDevicePopup?.isEnabled = enabled
        recordingMicrophoneDeviceTitleLabel?.textColor = Brand.text.withAlphaComponent(enabled ? 0.94 : 0.4)
    }

    @objc private func recordingMicrophoneDeviceChanged(_ sender: NSPopUpButton) {
        Defaults.recordingMicrophoneDeviceUID = sender.selectedItem?.representedObject as? String
    }

    private func buildShortcutsPane() -> NSView {
        let stack = paneStack()

        // Screenshot shortcut card
        let shortcut = buildShortcutCard(
            title: L10n.shortcutHeader,
            setAction: #selector(shortcutSetClicked),
            restoreAction: #selector(shortcutRestoreClicked)
        )
        shortcutTitleLabel = shortcut.title
        shortcutField = shortcut.field
        shortcutSetButton = shortcut.setButton
        shortcutRestoreButton = shortcut.restoreButton
        stack.addArrangedSubview(shortcut.card)
        shortcut.card.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        // Copy-to-clipboard (editor confirm) shortcut card
        let clipboardShortcut = buildShortcutCard(
            title: L10n.clipboardShortcutHeader,
            setAction: #selector(clipboardShortcutSetClicked),
            restoreAction: #selector(clipboardShortcutRestoreClicked)
        )
        clipboardShortcutTitleLabel = clipboardShortcut.title
        clipboardShortcutField = clipboardShortcut.field
        clipboardShortcutSetButton = clipboardShortcut.setButton
        clipboardShortcutRestoreButton = clipboardShortcut.restoreButton
        stack.addArrangedSubview(clipboardShortcut.card)
        clipboardShortcut.card.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        // Save-to-file shortcut card (default ⌘S)
        let fileSaveShortcut = buildShortcutCard(
            title: L10n.fileSaveShortcutHeader,
            setAction: #selector(fileSaveShortcutSetClicked),
            restoreAction: #selector(fileSaveShortcutRestoreClicked)
        )
        fileSaveShortcutTitleLabel = fileSaveShortcut.title
        fileSaveShortcutField = fileSaveShortcut.field
        fileSaveShortcutSetButton = fileSaveShortcut.setButton
        fileSaveShortcutRestoreButton = fileSaveShortcut.restoreButton
        stack.addArrangedSubview(fileSaveShortcut.card)
        fileSaveShortcut.card.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        // Full-screen screenshot shortcut card
        let fullScreenScreenshotShortcut = buildShortcutCard(
            title: L10n.fullScreenScreenshotShortcutHeader,
            setAction: #selector(fullScreenScreenshotShortcutSetClicked),
            restoreAction: #selector(fullScreenScreenshotShortcutRestoreClicked)
        )
        fullScreenScreenshotShortcutTitleLabel = fullScreenScreenshotShortcut.title
        fullScreenScreenshotShortcutField = fullScreenScreenshotShortcut.field
        fullScreenScreenshotShortcutSetButton = fullScreenScreenshotShortcut.setButton
        fullScreenScreenshotShortcutRestoreButton = fullScreenScreenshotShortcut.restoreButton
        stack.addArrangedSubview(fullScreenScreenshotShortcut.card)
        fullScreenScreenshotShortcut.card.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        // Color picker shortcut card
        let colorPickerShortcut = buildShortcutCard(
            title: L10n.colorPickerShortcutHeader,
            setAction: #selector(colorPickerShortcutSetClicked),
            restoreAction: #selector(colorPickerShortcutRestoreClicked)
        )
        colorPickerShortcutTitleLabel = colorPickerShortcut.title
        colorPickerShortcutField = colorPickerShortcut.field
        colorPickerShortcutSetButton = colorPickerShortcut.setButton
        colorPickerShortcutRestoreButton = colorPickerShortcut.restoreButton
        stack.addArrangedSubview(colorPickerShortcut.card)
        colorPickerShortcut.card.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        // Quick Pin shortcut card
        let quickPinShortcut = buildShortcutCard(
            title: L10n.quickPinShortcutHeader,
            setAction: #selector(quickPinShortcutSetClicked),
            restoreAction: #selector(quickPinShortcutRestoreClicked)
        )
        quickPinShortcutTitleLabel = quickPinShortcut.title
        quickPinShortcutField = quickPinShortcut.field
        quickPinShortcutSetButton = quickPinShortcut.setButton
        quickPinShortcutRestoreButton = quickPinShortcut.restoreButton
        quickPinShortcutRestoreButton.toolTip = L10n.quickPinShortcutClear
        stack.addArrangedSubview(quickPinShortcut.card)
        quickPinShortcut.card.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        // Text recognition shortcut card
        let textRecognitionShortcut = buildShortcutCard(
            title: L10n.textRecognitionShortcutHeader,
            setAction: #selector(textRecognitionShortcutSetClicked),
            restoreAction: #selector(textRecognitionShortcutRestoreClicked)
        )
        textRecognitionShortcutTitleLabel = textRecognitionShortcut.title
        textRecognitionShortcutField = textRecognitionShortcut.field
        textRecognitionShortcutSetButton = textRecognitionShortcut.setButton
        textRecognitionShortcutRestoreButton = textRecognitionShortcut.restoreButton
        stack.addArrangedSubview(textRecognitionShortcut.card)
        textRecognitionShortcut.card.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        // Copy image text shortcut card
        let copyImageTextShortcut = buildShortcutCard(
            title: L10n.copyImageTextShortcutHeader,
            setAction: #selector(copyImageTextShortcutSetClicked),
            restoreAction: #selector(copyImageTextShortcutRestoreClicked)
        )
        copyImageTextShortcutTitleLabel = copyImageTextShortcut.title
        copyImageTextShortcutField = copyImageTextShortcut.field
        copyImageTextShortcutSetButton = copyImageTextShortcut.setButton
        copyImageTextShortcutRestoreButton = copyImageTextShortcut.restoreButton
        stack.addArrangedSubview(copyImageTextShortcut.card)
        copyImageTextShortcut.card.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        // Recording shortcut card
        let recordShortcut = buildShortcutCard(
            title: L10n.recordShortcutHeader,
            setAction: #selector(recordShortcutSetClicked),
            restoreAction: #selector(recordShortcutRestoreClicked)
        )
        recordShortcutTitleLabel = recordShortcut.title
        recordShortcutField = recordShortcut.field
        recordShortcutSetButton = recordShortcut.setButton
        recordShortcutRestoreButton = recordShortcut.restoreButton
        stack.addArrangedSubview(recordShortcut.card)
        recordShortcut.card.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        let footer = NSStackView()
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 10
        footer.translatesAutoresizingMaskIntoConstraints = false

        let resetButton = NSButton(title: L10n.toolbarSettingsReset,
                                   target: self,
                                   action: #selector(shortcutsResetClicked))
        resetButton.bezelStyle = .rounded
        resetButton.controlSize = .large
        resetButton.translatesAutoresizingMaskIntoConstraints = false
        resetButton.setContentHuggingPriority(.required, for: .horizontal)
        shortcutResetButton = resetButton

        footer.addArrangedSubview(flexSpacer())
        footer.addArrangedSubview(resetButton)
        stack.addArrangedSubview(footer)
        footer.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        return wrapPane(stack)
    }

    private func buildScreenshotQualityCard(into stack: NSStackView) {
        let card = CardView()
        let inner = NSStackView()
        inner.orientation = .vertical
        inner.alignment = .leading
        inner.spacing = 10
        inner.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(inner)
        pin(inner, to: card, insets: NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14))

        let header = NSStackView()
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 3
        header.translatesAutoresizingMaskIntoConstraints = false

        screenshotQualityTitleLabel = primaryLabel(L10n.screenshotQualityTitle)
        screenshotQualitySubtitleLabel = secondaryLabel(L10n.screenshotQualitySubtitle, wrapping: true)
        header.addArrangedSubview(screenshotQualityTitleLabel)
        screenshotQualityTitleLabel.toolTip = L10n.screenshotQualitySubtitle
        inner.addArrangedSubview(header)
        header.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true

        let topDivider = rowDivider()
        inner.addArrangedSubview(topDivider)
        topDivider.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true

        let save = makeScreenshotQualityRow(
            title: L10n.screenshotQualitySaveLabel,
            quality: Defaults.screenshotSaveQuality,
            action: #selector(screenshotSaveQualityChanged(_:))
        )
        screenshotQualitySaveTitleLabel = save.title
        screenshotQualitySaveHintLabel = save.hint
        screenshotQualitySavePopup = save.popup
        inner.addArrangedSubview(save.row)
        save.row.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true

        let saveDivider = rowDivider()
        inner.addArrangedSubview(saveDivider)
        saveDivider.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true

        let clipboard = makeScreenshotQualityRow(
            title: L10n.screenshotQualityClipboardLabel,
            quality: Defaults.screenshotClipboardQuality,
            action: #selector(screenshotClipboardQualityChanged(_:))
        )
        screenshotQualityClipboardTitleLabel = clipboard.title
        screenshotQualityClipboardHintLabel = clipboard.hint
        screenshotQualityClipboardPopup = clipboard.popup
        inner.addArrangedSubview(clipboard.row)
        clipboard.row.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true

        refreshScreenshotQualityControls()

        stack.addArrangedSubview(card)
        card.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private func makeScreenshotQualityRow(
        title: String,
        quality: ScreenshotImageQuality,
        action: Selector
    ) -> (row: NSView, title: NSTextField, hint: NSTextField, popup: NSPopUpButton) {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false

        let labelStack = NSStackView()
        labelStack.orientation = .vertical
        labelStack.alignment = .leading
        labelStack.spacing = 3
        labelStack.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = primaryLabel(title)
        let hintLabel = secondaryLabel(quality.localizedHint, wrapping: true)
        labelStack.addArrangedSubview(titleLabel)
        row.addArrangedSubview(labelStack)
        labelStack.widthAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true

        row.addArrangedSubview(flexSpacer())

        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.controlSize = .small
        popup.font = NSFont.systemFont(ofSize: 12)
        popup.target = self
        popup.action = action
        popup.translatesAutoresizingMaskIntoConstraints = false
        popup.widthAnchor.constraint(greaterThanOrEqualToConstant: 140).isActive = true
        row.addArrangedSubview(popup)

        return (row, titleLabel, hintLabel, popup)
    }

    private func buildSavePathCard(into stack: NSStackView) {
        let card = CardView()
        let inner = NSStackView()
        inner.orientation = .vertical
        inner.alignment = .leading
        inner.spacing = 10
        inner.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(inner)
        pin(inner, to: card, insets: NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14))

        let header = NSStackView()
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 3
        header.translatesAutoresizingMaskIntoConstraints = false

        savePathTitleLabel = primaryLabel(L10n.savePathTitle)
        savePathSubtitleLabel = secondaryLabel(L10n.savePathSubtitle, wrapping: true)
        header.addArrangedSubview(savePathTitleLabel)
        savePathTitleLabel.toolTip = L10n.savePathSubtitle
        inner.addArrangedSubview(header)
        header.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true

        let topDivider = rowDivider()
        inner.addArrangedSubview(topDivider)
        topDivider.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true

        let screenshotPath = makeSavePathRow(
            title: L10n.screenshotSavePathLabel,
            chooseAction: #selector(chooseScreenshotSavePathClicked),
            revealAction: #selector(revealScreenshotSavePathClicked)
        )
        screenshotSavePathTitleLabel = screenshotPath.title
        screenshotSavePathValueLabel = screenshotPath.value
        screenshotSavePathChooseButton = screenshotPath.chooseButton
        screenshotSavePathRevealButton = screenshotPath.revealButton
        inner.addArrangedSubview(screenshotPath.row)
        screenshotPath.row.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true

        let pathDivider = rowDivider()
        inner.addArrangedSubview(pathDivider)
        pathDivider.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true

        let recordingPath = makeSavePathRow(
            title: L10n.recordingSavePathLabel,
            chooseAction: #selector(chooseRecordingSavePathClicked),
            revealAction: #selector(revealRecordingSavePathClicked)
        )
        recordingSavePathTitleLabel = recordingPath.title
        recordingSavePathValueLabel = recordingPath.value
        recordingSavePathChooseButton = recordingPath.chooseButton
        recordingSavePathRevealButton = recordingPath.revealButton
        inner.addArrangedSubview(recordingPath.row)
        recordingPath.row.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true

        let behaviorDivider = rowDivider()
        inner.addArrangedSubview(behaviorDivider)
        behaviorDivider.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true

        let askSave = makeToggleRow(
            title: L10n.askSaveLocationLabel,
            subtitle: L10n.askSaveLocationHint,
            isOn: Defaults.askSaveLocation,
            action: #selector(askSaveLocationToggled(_:))
        )
        askSaveLocationTitleLabel = askSave.title
        askSaveLocationHintLabel = askSave.subtitle
        askSaveLocationSwitch = askSave.toggle
        askSave.subtitle?.isHidden = true
        askSave.title.toolTip = L10n.askSaveLocationHint
        askSave.toggle.toolTip = L10n.askSaveLocationHint
        inner.addArrangedSubview(askSave.row)
        askSave.row.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true

        let askSaveDivider = rowDivider()
        inner.addArrangedSubview(askSaveDivider)
        askSaveDivider.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true

        let autoReveal = makeToggleRow(
            title: L10n.autoRevealSavedFilesLabel,
            subtitle: L10n.autoRevealSavedFilesHint,
            isOn: Defaults.autoRevealSavedFiles,
            action: #selector(autoRevealSavedFilesToggled(_:))
        )
        autoRevealSavedFilesTitleLabel = autoReveal.title
        autoRevealSavedFilesHintLabel = autoReveal.subtitle
        autoRevealSavedFilesSwitch = autoReveal.toggle
        autoReveal.subtitle?.isHidden = true
        autoReveal.title.toolTip = L10n.autoRevealSavedFilesHint
        autoReveal.toggle.toolTip = L10n.autoRevealSavedFilesHint
        inner.addArrangedSubview(autoReveal.row)
        autoReveal.row.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true

        refreshSavePathControls()
        stack.addArrangedSubview(card)
        card.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private func buildRecordingCard(into stack: NSStackView) {
        let card = CardView()
        let inner = paneStack()
        card.addSubview(inner)
        pin(inner, to: card, insets: NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14))
        let formatRow = NSStackView()
        formatRow.orientation = .horizontal
        formatRow.alignment = .centerY
        formatRow.spacing = 10
        formatRow.translatesAutoresizingMaskIntoConstraints = false

        recordingSaveFormatTitleLabel = primaryLabel(L10n.recordingSaveFormatSettingLabel)
        formatRow.addArrangedSubview(recordingSaveFormatTitleLabel)
        formatRow.addArrangedSubview(flexSpacer())

        recordingSaveFormatPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        recordingSaveFormatPopup.controlSize = .small
        recordingSaveFormatPopup.font = NSFont.systemFont(ofSize: 12)
        recordingSaveFormatPopup.target = self
        recordingSaveFormatPopup.action = #selector(recordingSaveFormatPreferenceChanged(_:))
        recordingSaveFormatPopup.translatesAutoresizingMaskIntoConstraints = false
        recordingSaveFormatPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
        formatRow.addArrangedSubview(recordingSaveFormatPopup)
        inner.addArrangedSubview(formatRow)
        formatRow.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true

        let audioDivider = rowDivider()
        inner.addArrangedSubview(audioDivider)
        audioDivider.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true

        let systemAudioToggle = makeToggleRow(
            title: L10n.recordingSystemAudioLabel,
            subtitle: L10n.recordingSystemAudioHint,
            isOn: Defaults.recordingSystemAudioEnabled,
            action: #selector(recordingSystemAudioToggled(_:))
        )
        recordingSystemAudioTitleLabel = systemAudioToggle.title
        recordingSystemAudioHintLabel = systemAudioToggle.subtitle
        recordingSystemAudioSwitch = systemAudioToggle.toggle
        inner.addArrangedSubview(systemAudioToggle.row)
        systemAudioToggle.row.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true

        let micDivider = rowDivider()
        inner.addArrangedSubview(micDivider)
        micDivider.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true

        let micToggle = makeToggleRow(
            title: L10n.recordingMicrophoneLabel,
            subtitle: L10n.recordingMicrophoneHint,
            isOn: Defaults.recordingMicrophoneEnabled,
            action: #selector(recordingMicrophoneToggled(_:))
        )
        recordingMicrophoneTitleLabel = micToggle.title
        recordingMicrophoneHintLabel = micToggle.subtitle
        recordingMicrophoneSwitch = micToggle.toggle
        inner.addArrangedSubview(micToggle.row)
        micToggle.row.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true

        let micDeviceDivider = rowDivider()
        inner.addArrangedSubview(micDeviceDivider)
        micDeviceDivider.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true

        let micDeviceRow = NSStackView()
        micDeviceRow.orientation = .horizontal
        micDeviceRow.alignment = .centerY
        micDeviceRow.spacing = 10
        micDeviceRow.translatesAutoresizingMaskIntoConstraints = false

        recordingMicrophoneDeviceTitleLabel = primaryLabel(L10n.recordingMicrophoneDeviceLabel)
        micDeviceRow.addArrangedSubview(recordingMicrophoneDeviceTitleLabel!)
        micDeviceRow.addArrangedSubview(flexSpacer())

        recordingMicrophoneDevicePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        recordingMicrophoneDevicePopup?.controlSize = .small
        recordingMicrophoneDevicePopup?.font = NSFont.systemFont(ofSize: 12)
        recordingMicrophoneDevicePopup?.target = self
        recordingMicrophoneDevicePopup?.action = #selector(recordingMicrophoneDeviceChanged(_:))
        recordingMicrophoneDevicePopup?.translatesAutoresizingMaskIntoConstraints = false
        recordingMicrophoneDevicePopup?.widthAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
        micDeviceRow.addArrangedSubview(recordingMicrophoneDevicePopup!)
        inner.addArrangedSubview(micDeviceRow)
        micDeviceRow.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true
        refreshMicrophoneDevicePopup()

        refreshRecordingSaveFormatPopup()
        updateMicrophoneControlsEnabled()
        stack.addArrangedSubview(card)
        card.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private func makeSavePathRow(
        title: String,
        chooseAction: Selector,
        revealAction: Selector
    ) -> (row: NSView, title: NSTextField, value: NSTextField, chooseButton: NSButton, revealButton: NSButton) {
        let row = NSStackView()
        row.orientation = .horizontal
        row.distribution = .fill
        row.alignment = .centerY
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = primaryLabel(title)
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        let valueLabel = secondaryLabel("", wrapping: false)
        valueLabel.isSelectable = true
        valueLabel.lineBreakMode = .byTruncatingMiddle
        valueLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        valueLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(titleLabel)
        row.addArrangedSubview(valueLabel)
        valueLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true

        let chooseButton = NSButton(title: L10n.savePathChoose, target: self, action: chooseAction)
        chooseButton.bezelStyle = .rounded
        chooseButton.controlSize = .small
        chooseButton.font = NSFont.systemFont(ofSize: 11)
        chooseButton.setContentHuggingPriority(.required, for: .horizontal)
        row.addArrangedSubview(chooseButton)

        let revealButton = NSButton(title: L10n.savePathReveal, target: self, action: revealAction)
        revealButton.bezelStyle = .rounded
        revealButton.controlSize = .small
        revealButton.font = NSFont.systemFont(ofSize: 11)
        revealButton.setContentHuggingPriority(.required, for: .horizontal)
        row.addArrangedSubview(revealButton)

        return (row, titleLabel, valueLabel, chooseButton, revealButton)
    }

    private func buildToolbarPane() -> NSView {
        let host = NSView()
        host.translatesAutoresizingMaskIntoConstraints = false
        let pane = ToolbarSettingsPane()
        toolbarPane = pane
        host.addSubview(pane)
        NSLayoutConstraint.activate([
            pane.topAnchor.constraint(equalTo: host.topAnchor),
            pane.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            pane.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            pane.bottomAnchor.constraint(equalTo: host.bottomAnchor),
        ])
        return host
    }

    func cancelToolbarShortcutRecording() {
        toolbarPane?.cancelShortcutRecording()
    }

    private func buildPermissionsPane() -> NSView {
        let stack = paneStack()

        let permCard = CardView()
        let permInner = verticalInnerStack()
        permCard.addSubview(permInner)
        pin(permInner, to: permCard, insets: NSEdgeInsets(top: 4, left: 0, bottom: 4, right: 0))

        let acc = makePermissionRow(
            name: L10n.accessibilityPermission,
            description: L10n.accessibilityDescription,
            action: #selector(openAccessibilitySettings(_:))
        )
        accessibilityNameLabel = acc.name
        accessibilityDescLabel = acc.desc
        accessibilityBadge = acc.badge
        permInner.addArrangedSubview(acc.row)
        acc.row.widthAnchor.constraint(equalTo: permInner.widthAnchor).isActive = true
        permInner.addArrangedSubview(rowDivider())

        let sc = makePermissionRow(
            name: L10n.screenRecordingPermission,
            description: L10n.screenRecordingDescription,
            action: #selector(openScreenRecordingSettings(_:))
        )
        screenRecordingNameLabel = sc.name
        screenRecordingDescLabel = sc.desc
        screenRecordingBadge = sc.badge
        permInner.addArrangedSubview(sc.row)
        sc.row.widthAnchor.constraint(equalTo: permInner.widthAnchor).isActive = true

        let micDivider = rowDivider()
        permInner.addArrangedSubview(micDivider)
        micDivider.widthAnchor.constraint(equalTo: permInner.widthAnchor).isActive = true

        // Microphone is optional: the Launch button is not gated on it, but
        // the row lets users grant it from Settings directly.
        let mic = makePermissionRow(
            name: L10n.microphonePermission,
            description: L10n.microphoneDescription,
            action: #selector(openMicrophoneSettings(_:))
        )
        microphoneNameLabel = mic.name
        microphoneDescLabel = mic.desc
        microphoneBadge = mic.badge
        permInner.addArrangedSubview(mic.row)
        mic.row.widthAnchor.constraint(equalTo: permInner.widthAnchor).isActive = true

        stack.addArrangedSubview(permCard)
        permCard.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        return wrapPane(stack)
    }

    private func buildAboutPane() -> NSView {
        let stack = paneStack()

        // Header card — app icon, name and version.
        let headerCard = CardView()
        let headerRow = NSStackView()
        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        headerRow.spacing = 14
        headerRow.translatesAutoresizingMaskIntoConstraints = false
        headerCard.addSubview(headerRow)
        pin(headerRow, to: headerCard, insets: NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16))

        let iconView = NSImageView()
        iconView.image = NSApp.applicationIconImage
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 56).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 56).isActive = true
        headerRow.addArrangedSubview(iconView)

        let nameLabel = NSTextField(labelWithString: "capcap")
        nameLabel.font = NSFont.systemFont(ofSize: 18, weight: .bold)
        nameLabel.textColor = Brand.text.withAlphaComponent(0.96)

        let versionLabel = NSTextField(labelWithString: appVersionString())
        versionLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        versionLabel.textColor = Brand.text.withAlphaComponent(0.55)

        let versionRow = NSStackView(views: [versionLabel, makeBuildConfigurationBadge()])
        versionRow.orientation = .horizontal
        versionRow.alignment = .centerY
        versionRow.spacing = 6

        let taglineLabel = secondaryLabel(L10n.aboutTagline, wrapping: true)
        aboutTaglineLabel = taglineLabel

        let textStack = NSStackView(views: [nameLabel, versionRow, taglineLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 3
        textStack.translatesAutoresizingMaskIntoConstraints = false
        headerRow.addArrangedSubview(textStack)
        headerRow.addArrangedSubview(flexSpacer())

        stack.addArrangedSubview(headerCard)
        headerCard.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        // Info card — license + source link rows.
        let infoCard = CardView()
        let infoInner = verticalInnerStack()
        infoCard.addSubview(infoInner)
        pin(infoInner, to: infoCard, insets: NSEdgeInsets(top: 4, left: 0, bottom: 4, right: 0))


        let license = makeInfoRow(title: L10n.aboutLicense, value: "MIT")
        aboutLicenseTitleLabel = license.title
        infoInner.addArrangedSubview(license.row)
        license.row.widthAnchor.constraint(equalTo: infoInner.widthAnchor).isActive = true
        infoInner.addArrangedSubview(rowDivider())

        let repo = makeLinkRow(
            title: L10n.aboutSourceCode,
            value: "github.com/realskyrin/capcap",
            action: #selector(openSourceRepo)
        )
        aboutSourceTitleLabel = repo.title
        infoInner.addArrangedSubview(repo.row)
        repo.row.widthAnchor.constraint(equalTo: infoInner.widthAnchor).isActive = true
        infoInner.addArrangedSubview(rowDivider())

        let star = makeLinkRow(
            title: L10n.aboutStarOnGitHub,
            value: "",
            action: #selector(openStarOnGitHub)
        )
        aboutStarTitleLabel = star.title
        infoInner.addArrangedSubview(star.row)
        star.row.widthAnchor.constraint(equalTo: infoInner.widthAnchor).isActive = true
        infoInner.addArrangedSubview(rowDivider())

        let featureRequest = makeLinkRow(
            title: L10n.aboutFeatureRequest,
            value: "",
            action: #selector(openFeatureRequest)
        )
        aboutFeatureRequestTitleLabel = featureRequest.title
        infoInner.addArrangedSubview(featureRequest.row)
        featureRequest.row.widthAnchor.constraint(equalTo: infoInner.widthAnchor).isActive = true
        infoInner.addArrangedSubview(rowDivider())

        let bugReport = makeLinkRow(
            title: L10n.aboutBugReport,
            value: "",
            action: #selector(openBugReport)
        )
        aboutBugReportTitleLabel = bugReport.title
        infoInner.addArrangedSubview(bugReport.row)
        bugReport.row.widthAnchor.constraint(equalTo: infoInner.widthAnchor).isActive = true

        stack.addArrangedSubview(infoCard)
        infoCard.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true


        return wrapPane(stack)
    }

    /// Static left-title / right-value row, mirroring the permission row chrome.
    private func makeInfoRow(title: String, value: String) -> (row: NSView, title: NSTextField) {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = primaryLabel(title)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let valueLabel = NSTextField(labelWithString: value)
        valueLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        valueLabel.textColor = Brand.text.withAlphaComponent(0.55)
        valueLabel.translatesAutoresizingMaskIntoConstraints = false

        row.addSubview(titleLabel)
        row.addSubview(valueLabel)
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 46),
            titleLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 14),
            titleLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            valueLabel.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -14),
            valueLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            valueLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 10),
        ])
        return (row, titleLabel)
    }

    /// Tappable row that opens an external URL, with a chevron affordance.
    private func makeLinkRow(title: String, value: String, action: Selector) -> (row: NSView, title: NSTextField) {
        let button = HoverButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.target = self
        button.action = action
        button.title = ""
        button.isBordered = false
        button.cornerRadius = 10

        let titleLabel = primaryLabel(title)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let valueLabel = NSTextField(labelWithString: value)
        valueLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        valueLabel.textColor = Brand.accent
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)

        let chevron = NSTextField(labelWithString: "\u{203A}")
        chevron.font = NSFont.systemFont(ofSize: 18, weight: .regular)
        chevron.textColor = Brand.text.withAlphaComponent(0.32)
        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.setContentHuggingPriority(.required, for: .horizontal)

        button.addSubview(titleLabel)
        button.addSubview(valueLabel)
        button.addSubview(chevron)
        NSLayoutConstraint.activate([
            button.heightAnchor.constraint(equalToConstant: 46),
            titleLabel.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 14),
            titleLabel.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            chevron.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -14),
            chevron.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            valueLabel.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -8),
            valueLabel.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            valueLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 10),
        ])
        return (button, titleLabel)
    }

    @objc private func openSourceRepo() {
        if let url = URL(string: "https://github.com/realskyrin/capcap") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openStarOnGitHub() {
        if let url = URL(string: "https://github.com/realskyrin/capcap") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openFeatureRequest() {
        if let url = URL(string: "https://github.com/realskyrin/capcap/issues/new?template=feature_request.yml") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openBugReport() {
        if let url = URL(string: "https://github.com/realskyrin/capcap/issues/new?template=bug_report.yml") {
            NSWorkspace.shared.open(url)
        }
    }

    private func paneStack() -> NSStackView {
        let s = NSStackView()
        s.orientation = .vertical
        s.alignment = .leading
        s.spacing = 12
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }

    private func wrapPane(_ stack: NSStackView) -> NSView {
        let host = NSView()
        host.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: host.topAnchor, constant: 4),
            stack.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -28),
            stack.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -28),
        ])
        return host
    }

    // MARK: - Builders

    private func verticalInnerStack() -> NSStackView {
        let s = NSStackView()
        s.orientation = .vertical
        s.alignment = .leading
        s.spacing = 0
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }

    private func rowDivider() -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.042).cgColor
        v.translatesAutoresizingMaskIntoConstraints = false
        v.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return v
    }

    private func flexSpacer() -> NSView {
        let v = NSView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.setContentHuggingPriority(.init(1), for: .horizontal)
        v.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        return v
    }

    private func primaryLabel(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        l.textColor = Brand.text
        return l
    }

    private func secondaryLabel(_ text: String, wrapping: Bool = false) -> NSTextField {
        let l = wrapping ? NSTextField(wrappingLabelWithString: text) : NSTextField(labelWithString: text)
        l.font = NSFont.systemFont(ofSize: 12)
        l.textColor = Brand.muted
        if wrapping {
            l.preferredMaxLayoutWidth = 360
        }
        return l
    }

    private func pin(_ child: NSView, to parent: NSView, insets: NSEdgeInsets) {
        NSLayoutConstraint.activate([
            child.topAnchor.constraint(equalTo: parent.topAnchor, constant: insets.top),
            child.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: insets.left),
            child.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -insets.right),
            child.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -insets.bottom),
        ])
    }

    private struct ShortcutCardBuild {
        let card: CardView
        let title: NSTextField
        let field: NSTextField
        let setButton: NSButton
        let restoreButton: NSButton
    }

    private func buildShortcutCard(
        title: String,
        setAction: Selector,
        restoreAction: Selector
    ) -> ShortcutCardBuild {
        let card = CardView()
        let inner = NSStackView()
        inner.orientation = .vertical
        inner.alignment = .leading
        inner.spacing = 8
        inner.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(inner)
        pin(inner, to: card, insets: NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14))

        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = primaryLabel(title)
        row.addArrangedSubview(titleLabel)
        row.addArrangedSubview(flexSpacer())

        let field = NSTextField()
        field.isEditable = false
        field.isSelectable = false
        field.isBordered = false
        field.drawsBackground = false
        field.alignment = .center
        field.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        field.textColor = Brand.text.withAlphaComponent(0.92)
        field.translatesAutoresizingMaskIntoConstraints = false

        let fieldBackground = NSView()
        fieldBackground.wantsLayer = true
        fieldBackground.layer?.cornerRadius = 5
        fieldBackground.layer?.cornerCurve = .continuous
        fieldBackground.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.056).cgColor
        fieldBackground.layer?.borderColor = NSColor.black.withAlphaComponent(0.07).cgColor
        fieldBackground.layer?.borderWidth = 1
        fieldBackground.translatesAutoresizingMaskIntoConstraints = false
        fieldBackground.addSubview(field)
        NSLayoutConstraint.activate([
            field.topAnchor.constraint(equalTo: fieldBackground.topAnchor, constant: 4),
            field.bottomAnchor.constraint(equalTo: fieldBackground.bottomAnchor, constant: -4),
            field.leadingAnchor.constraint(equalTo: fieldBackground.leadingAnchor, constant: 10),
            field.trailingAnchor.constraint(equalTo: fieldBackground.trailingAnchor, constant: -10),
            fieldBackground.widthAnchor.constraint(greaterThanOrEqualToConstant: 110),
        ])
        row.addArrangedSubview(fieldBackground)

        let setButton = NSButton(title: L10n.shortcutSet, target: self, action: setAction)
        setButton.bezelStyle = .rounded
        setButton.controlSize = .small
        setButton.font = NSFont.systemFont(ofSize: 12)
        setButton.translatesAutoresizingMaskIntoConstraints = false
        row.addArrangedSubview(setButton)

        let restoreButton = NSButton(
            image: NSImage(
                systemSymbolName: "arrow.counterclockwise.circle.fill",
                accessibilityDescription: L10n.shortcutRestore
            ) ?? NSImage(),
            target: self,
            action: restoreAction
        )
        restoreButton.bezelStyle = .inline
        restoreButton.isBordered = false
        restoreButton.imagePosition = .imageOnly
        restoreButton.contentTintColor = Brand.text.withAlphaComponent(0.62)
        restoreButton.toolTip = L10n.shortcutRestore
        restoreButton.translatesAutoresizingMaskIntoConstraints = false
        restoreButton.widthAnchor.constraint(equalToConstant: 22).isActive = true
        row.addArrangedSubview(restoreButton)

        inner.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true

        return ShortcutCardBuild(
            card: card,
            title: titleLabel,
            field: field,
            setButton: setButton,
            restoreButton: restoreButton
        )
    }

    private struct ToggleRowBuild {
        let row: NSView
        let title: NSTextField
        let subtitle: NSTextField?
        let toggle: NSSwitch
    }

    private func makeToggleRow(
        title: String,
        subtitle: String?,
        isOn: Bool,
        action: Selector
    ) -> ToggleRowBuild {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = primaryLabel(title)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.addArrangedSubview(titleLabel)

        var subtitleLabel: NSTextField? = nil
        if let subtitle {
            let sub = secondaryLabel(subtitle, wrapping: true)
            textStack.addArrangedSubview(sub)
            subtitleLabel = sub
        }

        let sw = NSSwitch()
        sw.state = isOn ? .on : .off
        sw.target = self
        sw.action = action
        sw.controlSize = .small
        sw.translatesAutoresizingMaskIntoConstraints = false

        row.addSubview(textStack)
        row.addSubview(sw)

        NSLayoutConstraint.activate([
            textStack.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            textStack.topAnchor.constraint(equalTo: row.topAnchor, constant: 10),
            textStack.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -10),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: sw.leadingAnchor, constant: -12),

            sw.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            sw.centerYAnchor.constraint(equalTo: textStack.centerYAnchor),
        ])

        return ToggleRowBuild(row: row, title: titleLabel, subtitle: subtitleLabel, toggle: sw)
    }

    private struct RadioRowBuild {
        let row: NSView
        let title: NSTextField
        let subtitle: NSTextField?
        let button: NSButton
    }

    private func makeRadioRow(
        title: String,
        subtitle: String?,
        isOn: Bool,
        action: Selector
    ) -> RadioRowBuild {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = primaryLabel(title)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.addArrangedSubview(titleLabel)

        var subtitleLabel: NSTextField? = nil
        if let subtitle {
            let sub = secondaryLabel(subtitle, wrapping: true)
            textStack.addArrangedSubview(sub)
            subtitleLabel = sub
        }

        let button = NSButton(radioButtonWithTitle: "", target: self, action: action)
        button.state = isOn ? .on : .off
        button.controlSize = .small
        button.translatesAutoresizingMaskIntoConstraints = false

        row.addSubview(textStack)
        row.addSubview(button)

        NSLayoutConstraint.activate([
            textStack.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            textStack.topAnchor.constraint(equalTo: row.topAnchor, constant: 10),
            textStack.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -10),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: button.leadingAnchor, constant: -12),

            button.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            button.centerYAnchor.constraint(equalTo: textStack.centerYAnchor),
        ])

        return RadioRowBuild(row: row, title: titleLabel, subtitle: subtitleLabel, button: button)
    }

    private struct PermissionRowBuild {
        let row: NSView
        let name: NSTextField
        let desc: NSTextField
        let badge: StatusBadge
    }

    private func makePermissionRow(
        name: String,
        description: String,
        action: Selector
    ) -> PermissionRowBuild {
        let button = HoverButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.target = self
        button.action = action
        button.title = ""
        button.isBordered = false
        button.cornerRadius = 10

        let nameLbl = primaryLabel(name)
        nameLbl.translatesAutoresizingMaskIntoConstraints = false

        let badge = StatusBadge()
        badge.translatesAutoresizingMaskIntoConstraints = false

        let topLine = NSStackView(views: [nameLbl, badge])
        topLine.orientation = .horizontal
        topLine.alignment = .centerY
        topLine.spacing = 8
        topLine.translatesAutoresizingMaskIntoConstraints = false

        let descLbl = secondaryLabel(description, wrapping: true)
        descLbl.translatesAutoresizingMaskIntoConstraints = false

        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 4
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.addArrangedSubview(topLine)
        textStack.addArrangedSubview(descLbl)

        let chevron = NSTextField(labelWithString: "\u{203A}")
        chevron.font = NSFont.systemFont(ofSize: 18, weight: .regular)
        chevron.textColor = Brand.text.withAlphaComponent(0.32)
        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.setContentHuggingPriority(.required, for: .horizontal)

        button.addSubview(textStack)
        button.addSubview(chevron)
        NSLayoutConstraint.activate([
            textStack.topAnchor.constraint(equalTo: button.topAnchor, constant: 12),
            textStack.bottomAnchor.constraint(equalTo: button.bottomAnchor, constant: -12),
            textStack.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 14),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: chevron.leadingAnchor, constant: -10),

            chevron.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            chevron.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -14),
        ])

        return PermissionRowBuild(row: button, name: nameLbl, desc: descLbl, badge: badge)
    }

    private func updateLaunchButtonVisibility() {
        // The bottom action is always visible now — its title and enablement
        // flips between Launch (startup mode) and Quit (regular mode).
        refreshBottomAction()
    }

    private func refreshBottomAction() {
        guard let btn = launchButton else { return }
        if isStartup {
            // Accessibility is enough to start: the ⌘⌘ trigger needs it, and a
            // missing Screen Recording grant is requested on the first capture.
            btn.update(symbolName: "power", title: L10n.launchApp, tint: Brand.accent, prominent: true)
            btn.isEnabled = AppPermissions.accessibilityGranted
        } else {
            // Red tint — actual destructive confirmation happens in the NSAlert
            // sheet that fires on click.
            btn.update(symbolName: "power", title: L10n.settingsQuit, tint: Brand.muted, prominent: false)
            btn.isEnabled = true
        }
    }

    func setStartupMode(_ startup: Bool) {
        let wasStartup = isStartup
        isStartup = startup
        updateLaunchButtonVisibility()
        if startup {
            selectTab(.permissions)
        } else if wasStartup && selectedTab == .permissions && AppPermissions.allRequiredGranted {
            selectTab(.general)
        }
    }

    func showPermissionsTab() {
        selectTab(.permissions)
    }

    // MARK: - Permission polling

    private func startRefreshTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.refreshPermissionStatus()
        }
    }

    func refreshPermissionStatus() {
        let accessibilityGranted = AppPermissions.accessibilityGranted
        let screenRecordingGranted = AppPermissions.screenRecordingGranted

        accessibilityBadge?.configure(granted: accessibilityGranted)
        screenRecordingBadge?.configure(granted: screenRecordingGranted)
        microphoneBadge?.configure(granted: AppPermissions.microphoneGranted)

        // Only the startup-mode Launch button is gated on permissions; the
        // regular-mode Quit button stays enabled.
        if isStartup {
            refreshBottomAction()
        }
    }

    // MARK: - Actions

    @objc private func languageChanged(_ sender: NSPopUpButton) {
        let cases = AppLanguage.allCases
        let index = sender.indexOfSelectedItem
        guard cases.indices.contains(index) else { return }
        Defaults.language = cases[index]
        // The change notification relabels the whole pane; make sure the
        // picker itself still shows the choice afterwards.
        sender.selectItem(at: index)
        sender.synchronizeTitleAndSelectedItem()
        sender.needsDisplay = true
    }

    @objc private func recordingSaveFormatPreferenceChanged(_ sender: NSPopUpButton) {
        guard let raw = sender.selectedItem?.representedObject as? String,
              let preference = RecordingSavePreference(rawValue: raw)
        else {
            return
        }
        Defaults.recordingSavePreference = preference
    }

    @objc private func screenshotSaveQualityChanged(_ sender: NSPopUpButton) {
        guard let quality = selectedScreenshotQuality(from: sender) else { return }
        Defaults.screenshotSaveQuality = quality
        refreshScreenshotQualityControls()
    }

    @objc private func screenshotClipboardQualityChanged(_ sender: NSPopUpButton) {
        guard let quality = selectedScreenshotQuality(from: sender) else { return }
        Defaults.screenshotClipboardQuality = quality
        refreshScreenshotQualityControls()
    }

    private func selectedScreenshotQuality(from sender: NSPopUpButton) -> ScreenshotImageQuality? {
        guard let raw = sender.selectedItem?.representedObject as? String else { return nil }
        return ScreenshotImageQuality(rawValue: raw)
    }

    @objc private func askSaveLocationToggled(_ sender: NSSwitch) {
        Defaults.askSaveLocation = sender.state == .on
    }

    @objc private func autoRevealSavedFilesToggled(_ sender: NSSwitch) {
        Defaults.autoRevealSavedFiles = sender.state == .on
    }

    @objc private func chooseRecordingSavePathClicked() {
        chooseSaveDirectory(
            title: L10n.chooseRecordingSavePathTitle,
            currentURL: Defaults.recordingSaveDirectory
        ) { url in
            Defaults.recordingSaveDirectory = url
            self.refreshSavePathControls()
        }
    }

    @objc private func chooseScreenshotSavePathClicked() {
        chooseSaveDirectory(
            title: L10n.chooseScreenshotSavePathTitle,
            currentURL: Defaults.screenshotSaveDirectory
        ) { url in
            Defaults.screenshotSaveDirectory = url
            self.refreshSavePathControls()
        }
    }

    @objc private func revealRecordingSavePathClicked() {
        revealSaveDirectory(Defaults.recordingSaveDirectory)
    }

    @objc private func revealScreenshotSavePathClicked() {
        revealSaveDirectory(Defaults.screenshotSaveDirectory)
    }

    private func chooseSaveDirectory(
        title: String,
        currentURL: URL,
        completion: @escaping (URL) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.title = title
        panel.prompt = L10n.savePathChoose
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = directoryURLForPanel(currentURL)

        let handle: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            completion(url)
        }

        if let window {
            panel.beginSheetModal(for: window, completionHandler: handle)
        } else {
            panel.begin(completionHandler: handle)
        }
    }

    private func directoryURLForPanel(_ url: URL) -> URL {
        if FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        let parent = url.deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: parent.path) {
            return parent
        }
        return Defaults.defaultScreenshotSaveDirectory.deletingLastPathComponent()
    }

    private func revealSaveDirectory(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func historyCacheSliderChanged(_ sender: SettingsTickSlider) {
        guard Defaults.historyCacheEnabled else {
            sender.doubleValue = Double(Defaults.historyCacheLimit)
            return
        }
        let value = Int(sender.doubleValue.rounded())
        Defaults.historyCacheLimit = value
        let normalizedValue = Defaults.historyCacheLimit
        sender.doubleValue = Double(normalizedValue)
        historyCacheValueLabel?.stringValue = "\(normalizedValue)"
    }

    @objc private func clipboardTextHistoryLimitSliderChanged(_ sender: SettingsTickSlider) {
        guard Defaults.clipboardTextCacheEnabled else {
            sender.doubleValue = Double(Defaults.clipboardTextHistoryLimit)
            return
        }
        Defaults.clipboardTextHistoryLimit = Int(sender.doubleValue.rounded())
        let normalizedValue = Defaults.clipboardTextHistoryLimit
        sender.doubleValue = Double(normalizedValue)
        clipboardTextHistoryLimitValueLabel?.stringValue = "\(normalizedValue)"
    }

    @objc private func historyCacheToggled(_ sender: NSSwitch) {
        Defaults.historyCacheEnabled = sender.state == .on
    }

    @objc private func clipboardTextCacheToggled(_ sender: NSSwitch) {
        Defaults.clipboardTextCacheEnabled = sender.state == .on
    }

    @objc private func historyNotchTriggerChanged(_ sender: NSPopUpButton) {
        let modes = Defaults.HistoryNotchTriggerMode.allCases
        guard modes.indices.contains(sender.indexOfSelectedItem) else { return }
        Defaults.historyNotchTriggerMode = modes[sender.indexOfSelectedItem]
    }

    @objc private func historyPanelModeOptionClicked(_ sender: HistoryPanelModeOptionView) {
        guard Defaults.isHistoryCacheAvailable else { return }
        switch sender.mode {
        case .dialog:
            Defaults.historyPanelDialogEnabled = true
        case .notch:
            guard Defaults.historyPanelNotchAvailable else {
                return
            }
            Defaults.historyPanelNotchEnabled = true
        }
    }

    @objc private func screenParametersChanged() {
    }

    @objc private func countdownSliderChanged(_ sender: SettingsTickSlider) {
        let value = Int(sender.doubleValue.rounded())
        Defaults.countdownSeconds = value
        countdownValueLabel?.stringValue = "\(Defaults.countdownSeconds)\(L10n.countdownSecondsSuffix)"
    }

    @objc private func windowShadowToggled(_ sender: NSSwitch) {
        Defaults.windowShadowEnabled = sender.state == .on
        updateWindowShadowControlsEnabled()
    }

    @objc private func recordingSystemAudioToggled(_ sender: NSSwitch) {
        Defaults.recordingSystemAudioEnabled = sender.state == .on
    }

    @objc private func recordingMicrophoneToggled(_ sender: NSSwitch) {
        let enabled = sender.state == .on
        Defaults.recordingMicrophoneEnabled = enabled
        updateMicrophoneControlsEnabled()
        guard enabled else { return }

        // Once denied, macOS won't re-prompt — bounce to System Settings and
        // revert the toggle so the UI stays truthful.
        if AppPermissions.microphoneGranted {
            return
        }
        if AppPermissions.microphoneDenied {
            sender.state = .off
            Defaults.recordingMicrophoneEnabled = false
            updateMicrophoneControlsEnabled()
            presentMicrophoneDeniedAlert()
            return
        }
        AppPermissions.requestMicrophonePermission { [weak self] granted in
            guard let self else { return }
            if granted {
                self.refreshPermissionStatus()
                return
            }
            // User declined the prompt or an error occurred. Revert.
            self.recordingMicrophoneSwitch?.state = .off
            Defaults.recordingMicrophoneEnabled = false
            self.updateMicrophoneControlsEnabled()
            self.refreshPermissionStatus()
        }
    }

    private func presentMicrophoneDeniedAlert() {
        guard let win = self.window else { return }
        let alert = NSAlert()
        alert.messageText = L10n.recordingMicrophoneDeniedTitle
        alert.informativeText = L10n.recordingMicrophoneDeniedMessage
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.recordingMicrophoneOpenSettings)
        alert.addButton(withTitle: L10n.shortcutCancel)
        alert.beginSheetModal(for: win) { response in
            if response == .alertFirstButtonReturn {
                self.openMicrophoneSystemSettings()
            }
        }
    }

    @objc private func windowShadowSizeChanged(_ sender: NSSlider) {
        Defaults.windowShadowSize = sender.doubleValue
        windowShadowSizeValueLabel?.stringValue = "\(Int(Defaults.windowShadowSize.rounded()))"
        windowShadowPreview?.shadowSize = CGFloat(Defaults.windowShadowSize)
    }

    @objc private func launchAtLoginToggled(_ sender: NSSwitch) {
        let enable = sender.state == .on
        let ok = LaunchAtLogin.setEnabled(enable)
        if !ok {
            sender.state = LaunchAtLogin.isEnabled ? .on : .off
        }
    }

    @objc private func pinAcrossSpacesToggled(_ sender: NSSwitch) {
        Defaults.pinAcrossSpaces = sender.state == .on
    }

    @objc private func menuBarSwitchToggled(_ sender: NSSwitch) {
        let visible = sender.state == .on
        Defaults.showMenuBar = visible
        onMenuBarToggle?(visible)
    }

    @objc private func openAccessibilitySettings(_ sender: NSButton) {
        startPermissionFlow(.accessibility, from: sender)
    }

    @objc private func openScreenRecordingSettings(_ sender: NSButton) {
        // On macOS 15+ the app only appears in the Screen Recording list after
        // it asks the system once; a bare deep link leaves nothing to toggle.
        if CGRequestScreenCaptureAccess() {
            refreshPermissionStatus()
            return
        }
        startPermissionFlow(.screenRecording, from: sender)
    }

    @objc private func openMicrophoneSettings(_ sender: NSButton) {
        // Microphone is optional and macOS will not re-prompt once a decision
        // has been made. If a decision is still pending, request inline; if it
        // was already denied, jump straight to System Settings.
        if AppPermissions.microphoneGranted {
            return
        }
        if AppPermissions.microphoneDenied {
            openMicrophoneSystemSettings()
            return
        }
        AppPermissions.requestMicrophonePermission { [weak self] granted in
            guard let self else { return }
            self.refreshPermissionStatus()
            if !granted {
                self.openMicrophoneSystemSettings()
            }
        }
    }

    private func openMicrophoneSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Microphone") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func startPermissionFlow(_ pane: PermissionFlowPane, from sourceView: NSView) {
        permissionFlowController.setLocaleIdentifier(Defaults.language.lprojName)
        updateMicrophoneControlsEnabled()
        permissionFlowController.authorize(
            pane: pane,
            suggestedAppURLs: [Bundle.main.bundleURL],
            sourceFrameInScreen: sourceFrameInScreen(for: sourceView)
        )
    }

    private func sourceFrameInScreen(for view: NSView) -> CGRect? {
        guard let window = view.window else { return nil }
        let frameInWindow = view.convert(view.bounds, to: nil)
        return window.convertToScreen(frameInWindow)
    }

    func closePermissionFlowPanel() {
        permissionFlowController.closePanel()
    }

    @objc private func launchClicked() {
        if isStartup {
            guard AppPermissions.accessibilityGranted else {
                showPermissionsTab()
                refreshPermissionStatus()
                return
            }
            refreshTimer?.invalidate()
            refreshTimer = nil
            onLaunch?()
        } else {
            confirmQuit()
        }
    }

    private func confirmQuit() {
        let alert = NSAlert()
        alert.messageText = L10n.quitConfirmTitle
        alert.informativeText = L10n.quitConfirmMessage
        alert.alertStyle = .warning
        let quitBtn = alert.addButton(withTitle: L10n.quitConfirmAction)
        if #available(macOS 11.0, *) {
            quitBtn.hasDestructiveAction = true
        }
        let cancelBtn = alert.addButton(withTitle: L10n.quitConfirmCancel)
        cancelBtn.keyEquivalent = "\u{1b}" // Escape

        let handle: (NSApplication.ModalResponse) -> Void = { response in
            if response == .alertFirstButtonReturn {
                NSApp.terminate(nil)
            }
        }
        if let win = self.window {
            alert.beginSheetModal(for: win, completionHandler: handle)
        } else {
            handle(alert.runModal())
        }
    }

    // MARK: - Shortcut recording

    /// Tells the user a recorded combo is already taken by another function,
    /// so they can pick a different one. Recording is already cancelled by the
    /// caller before this is shown.
    private func presentHotkeyConflictAlert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = L10n.shortcutConflictTitle
        alert.informativeText = message
        alert.alertStyle = .warning
        if let win = self.window {
            alert.beginSheetModal(for: win, completionHandler: nil)
        } else {
            alert.runModal()
        }
    }

    /// Tells the user a recorded key needs a modifier held with it, so they
    /// can try again. Recording is already cancelled by the caller before
    /// this is shown.
    private func presentShortcutNeedsModifierAlert() {
        let alert = NSAlert()
        alert.messageText = L10n.shortcutNeedsModifierTitle
        alert.informativeText = L10n.shortcutNeedsModifier
        alert.alertStyle = .warning
        if let win = self.window {
            alert.beginSheetModal(for: win, completionHandler: nil)
        } else {
            alert.runModal()
        }
    }

    private func cancelShortcutRecordings(except slot: HotkeyManager.HotkeySlot) {
        if slot != .screenshot, shortcutRecordingMonitor != nil {
            cancelShortcutRecording()
        }
        if slot != .fullScreenScreenshot, fullScreenScreenshotShortcutRecordingMonitor != nil {
            cancelFullScreenScreenshotShortcutRecording()
        }
        if slot != .colorPicker, colorPickerShortcutRecordingMonitor != nil {
            cancelColorPickerShortcutRecording()
        }
        if slot != .quickPin, quickPinShortcutRecordingMonitor != nil {
            cancelQuickPinShortcutRecording()
        }
        if slot != .textRecognition, textRecognitionShortcutRecordingMonitor != nil {
            cancelTextRecognitionShortcutRecording()
        }
        if slot != .copyImageText, copyImageTextShortcutRecordingMonitor != nil {
            cancelCopyImageTextShortcutRecording()
        }
        if slot != .record, recordShortcutRecordingMonitor != nil {
            cancelRecordShortcutRecording()
        }
        if slot != .clipboard, clipboardShortcutRecordingMonitor != nil {
            cancelClipboardShortcutRecording()
        }
        if slot != .fileSave, fileSaveShortcutRecordingMonitor != nil {
            cancelFileSaveShortcutRecording()
        }
    }

    @objc private func shortcutSetClicked() {
        if shortcutRecordingMonitor != nil {
            cancelShortcutRecording()
            return
        }
        cancelShortcutRecordings(except: .screenshot)
        HotkeyManager.shared.beginRecording()
        shortcutSetButton.title = L10n.shortcutCancel
        shortcutField.stringValue = L10n.shortcutWaiting
        shortcutRestoreButton.isHidden = true

        shortcutRecordingMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            let modifiers = event.modifierFlags
            let isEscape = event.keyCode == UInt16(kVK_Escape)
            let activeModifierMask: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
            let pressedModifiers = modifiers.intersection(activeModifierMask)

            if isEscape && pressedModifiers.isEmpty {
                self.cancelShortcutRecording()
                return nil
            }

            var carbonMods: UInt32 = 0
            if modifiers.contains(.command) { carbonMods |= UInt32(cmdKey) }
            if modifiers.contains(.shift)   { carbonMods |= UInt32(shiftKey) }
            if modifiers.contains(.option)  { carbonMods |= UInt32(optionKey) }
            if modifiers.contains(.control) { carbonMods |= UInt32(controlKey) }
            let keyCode = UInt32(event.keyCode)

            // Reject bare keys (no modifier and not a function key) — the user must
            // hold at least one modifier so the shortcut won't collide with typing.
            if carbonMods == 0 && !HotkeyManager.isFunctionKey(keyCode) {
                self.cancelShortcutRecording()
                self.presentShortcutNeedsModifierAlert()
                return nil
            }

            if let conflict = HotkeyManager.shared.hotkeyConflictMessage(
                forKeyCode: keyCode, modifiers: carbonMods, assigningTo: .screenshot) {
                self.cancelShortcutRecording()
                self.presentHotkeyConflictAlert(conflict)
                return nil
            }

            Defaults.screenshotHotkeyKeyCode = Int(keyCode)
            Defaults.screenshotHotkeyModifiers = Int(carbonMods)
            self.finishShortcutRecording()
            return nil
        }
    }

    @objc private func shortcutRestoreClicked() {
        if shortcutRecordingMonitor != nil {
            cancelShortcutRecording()
        }
        Defaults.clearScreenshotHotkey()
        NotificationCenter.default.post(name: .hotkeyDidChange, object: nil)
        refreshShortcutDisplay()
    }

    private func finishShortcutRecording() {
        if let m = shortcutRecordingMonitor {
            NSEvent.removeMonitor(m)
            shortcutRecordingMonitor = nil
        }
        HotkeyManager.shared.endRecording()
        refreshShortcutDisplay()
    }

    func cancelShortcutRecording() {
        guard shortcutRecordingMonitor != nil else { return }
        if let m = shortcutRecordingMonitor {
            NSEvent.removeMonitor(m)
            shortcutRecordingMonitor = nil
        }
        HotkeyManager.shared.endRecording()
        refreshShortcutDisplay()
    }

    private func refreshShortcutDisplay() {
        shortcutSetButton?.title = L10n.shortcutSet
        if let display = HotkeyManager.currentDisplayString() {
            shortcutField?.stringValue = display
            shortcutRestoreButton?.isHidden = false
        } else {
            shortcutField?.stringValue = L10n.shortcutDefaultDisplay
            shortcutRestoreButton?.isHidden = true
        }
    }

    @objc private func fullScreenScreenshotShortcutSetClicked() {
        if fullScreenScreenshotShortcutRecordingMonitor != nil {
            cancelFullScreenScreenshotShortcutRecording()
            return
        }
        cancelShortcutRecordings(except: .fullScreenScreenshot)
        HotkeyManager.shared.beginRecording()
        fullScreenScreenshotShortcutSetButton.title = L10n.shortcutCancel
        fullScreenScreenshotShortcutField.stringValue = L10n.shortcutWaiting
        fullScreenScreenshotShortcutRestoreButton.isHidden = true

        fullScreenScreenshotShortcutRecordingMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            let modifiers = event.modifierFlags
            let isEscape = event.keyCode == UInt16(kVK_Escape)
            let activeModifierMask: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
            let pressedModifiers = modifiers.intersection(activeModifierMask)

            if isEscape && pressedModifiers.isEmpty {
                self.cancelFullScreenScreenshotShortcutRecording()
                return nil
            }

            var carbonMods: UInt32 = 0
            if modifiers.contains(.command) { carbonMods |= UInt32(cmdKey) }
            if modifiers.contains(.shift)   { carbonMods |= UInt32(shiftKey) }
            if modifiers.contains(.option)  { carbonMods |= UInt32(optionKey) }
            if modifiers.contains(.control) { carbonMods |= UInt32(controlKey) }
            let keyCode = UInt32(event.keyCode)

            if carbonMods == 0 && !HotkeyManager.isFunctionKey(keyCode) {
                self.cancelFullScreenScreenshotShortcutRecording()
                self.presentShortcutNeedsModifierAlert()
                return nil
            }

            if let conflict = HotkeyManager.shared.hotkeyConflictMessage(
                forKeyCode: keyCode, modifiers: carbonMods, assigningTo: .fullScreenScreenshot) {
                self.cancelFullScreenScreenshotShortcutRecording()
                self.presentHotkeyConflictAlert(conflict)
                return nil
            }

            Defaults.fullScreenScreenshotHotkeyKeyCode = Int(keyCode)
            Defaults.fullScreenScreenshotHotkeyModifiers = Int(carbonMods)
            self.finishFullScreenScreenshotShortcutRecording()
            return nil
        }
    }

    @objc private func fullScreenScreenshotShortcutRestoreClicked() {
        if fullScreenScreenshotShortcutRecordingMonitor != nil {
            cancelFullScreenScreenshotShortcutRecording()
        }
        Defaults.clearFullScreenScreenshotHotkey()
        NotificationCenter.default.post(name: .hotkeyDidChange, object: nil)
        refreshFullScreenScreenshotShortcutDisplay()
    }

    private func finishFullScreenScreenshotShortcutRecording() {
        if let m = fullScreenScreenshotShortcutRecordingMonitor {
            NSEvent.removeMonitor(m)
            fullScreenScreenshotShortcutRecordingMonitor = nil
        }
        HotkeyManager.shared.endRecording()
        refreshFullScreenScreenshotShortcutDisplay()
    }

    func cancelFullScreenScreenshotShortcutRecording() {
        guard fullScreenScreenshotShortcutRecordingMonitor != nil else { return }
        if let m = fullScreenScreenshotShortcutRecordingMonitor {
            NSEvent.removeMonitor(m)
            fullScreenScreenshotShortcutRecordingMonitor = nil
        }
        HotkeyManager.shared.endRecording()
        refreshFullScreenScreenshotShortcutDisplay()
    }

    private func refreshFullScreenScreenshotShortcutDisplay() {
        fullScreenScreenshotShortcutSetButton?.title = L10n.shortcutSet
        if let display = HotkeyManager.currentFullScreenScreenshotDisplayString() {
            fullScreenScreenshotShortcutField?.stringValue = display
            fullScreenScreenshotShortcutRestoreButton?.isHidden = false
        } else {
            fullScreenScreenshotShortcutField?.stringValue = L10n.fullScreenScreenshotShortcutDefaultDisplay
            fullScreenScreenshotShortcutRestoreButton?.isHidden = true
        }
    }

    @objc private func colorPickerShortcutSetClicked() {
        if colorPickerShortcutRecordingMonitor != nil {
            cancelColorPickerShortcutRecording()
            return
        }
        cancelShortcutRecordings(except: .colorPicker)
        HotkeyManager.shared.beginRecording()
        colorPickerShortcutSetButton.title = L10n.shortcutCancel
        colorPickerShortcutField.stringValue = L10n.shortcutWaiting
        colorPickerShortcutRestoreButton.isHidden = true

        colorPickerShortcutRecordingMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            let modifiers = event.modifierFlags
            let isEscape = event.keyCode == UInt16(kVK_Escape)
            let activeModifierMask: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
            let pressedModifiers = modifiers.intersection(activeModifierMask)

            if isEscape && pressedModifiers.isEmpty {
                self.cancelColorPickerShortcutRecording()
                return nil
            }

            var carbonMods: UInt32 = 0
            if modifiers.contains(.command) { carbonMods |= UInt32(cmdKey) }
            if modifiers.contains(.shift)   { carbonMods |= UInt32(shiftKey) }
            if modifiers.contains(.option)  { carbonMods |= UInt32(optionKey) }
            if modifiers.contains(.control) { carbonMods |= UInt32(controlKey) }
            let keyCode = UInt32(event.keyCode)

            if carbonMods == 0 && !HotkeyManager.isFunctionKey(keyCode) {
                self.cancelColorPickerShortcutRecording()
                self.presentShortcutNeedsModifierAlert()
                return nil
            }

            if let conflict = HotkeyManager.shared.hotkeyConflictMessage(
                forKeyCode: keyCode, modifiers: carbonMods, assigningTo: .colorPicker) {
                self.cancelColorPickerShortcutRecording()
                self.presentHotkeyConflictAlert(conflict)
                return nil
            }

            Defaults.colorPickerHotkeyKeyCode = Int(keyCode)
            Defaults.colorPickerHotkeyModifiers = Int(carbonMods)
            self.finishColorPickerShortcutRecording()
            return nil
        }
    }

    @objc private func colorPickerShortcutRestoreClicked() {
        if colorPickerShortcutRecordingMonitor != nil {
            cancelColorPickerShortcutRecording()
        }
        Defaults.clearColorPickerHotkey()
        NotificationCenter.default.post(name: .hotkeyDidChange, object: nil)
        refreshColorPickerShortcutDisplay()
    }

    private func finishColorPickerShortcutRecording() {
        if let m = colorPickerShortcutRecordingMonitor {
            NSEvent.removeMonitor(m)
            colorPickerShortcutRecordingMonitor = nil
        }
        HotkeyManager.shared.endRecording()
        refreshColorPickerShortcutDisplay()
    }

    func cancelColorPickerShortcutRecording() {
        guard colorPickerShortcutRecordingMonitor != nil else { return }
        if let m = colorPickerShortcutRecordingMonitor {
            NSEvent.removeMonitor(m)
            colorPickerShortcutRecordingMonitor = nil
        }
        HotkeyManager.shared.endRecording()
        refreshColorPickerShortcutDisplay()
    }

    private func refreshColorPickerShortcutDisplay() {
        colorPickerShortcutSetButton?.title = L10n.shortcutSet
        if let display = HotkeyManager.currentColorPickerDisplayString() {
            colorPickerShortcutField?.stringValue = display
            colorPickerShortcutRestoreButton?.isHidden = false
        } else {
            colorPickerShortcutField?.stringValue = L10n.colorPickerShortcutDefaultDisplay
            colorPickerShortcutRestoreButton?.isHidden = true
        }
    }

    @objc private func quickPinShortcutSetClicked() {
        if quickPinShortcutRecordingMonitor != nil {
            cancelQuickPinShortcutRecording()
            return
        }
        cancelShortcutRecordings(except: .quickPin)
        HotkeyManager.shared.beginRecording()
        quickPinShortcutSetButton.title = L10n.shortcutCancel
        quickPinShortcutField.stringValue = L10n.shortcutWaiting
        quickPinShortcutRestoreButton.isHidden = true

        quickPinShortcutRecordingMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let modifiers = event.modifierFlags
            let isEscape = event.keyCode == UInt16(kVK_Escape)
            let activeModifierMask: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
            let pressedModifiers = modifiers.intersection(activeModifierMask)

            if isEscape && pressedModifiers.isEmpty {
                self.cancelQuickPinShortcutRecording()
                return nil
            }

            var carbonMods: UInt32 = 0
            if modifiers.contains(.command) { carbonMods |= UInt32(cmdKey) }
            if modifiers.contains(.shift)   { carbonMods |= UInt32(shiftKey) }
            if modifiers.contains(.option)  { carbonMods |= UInt32(optionKey) }
            if modifiers.contains(.control) { carbonMods |= UInt32(controlKey) }
            let keyCode = UInt32(event.keyCode)

            if carbonMods == 0 && !HotkeyManager.isFunctionKey(keyCode) {
                self.cancelQuickPinShortcutRecording()
                self.presentShortcutNeedsModifierAlert()
                return nil
            }

            if let conflict = HotkeyManager.shared.hotkeyConflictMessage(
                forKeyCode: keyCode, modifiers: carbonMods, assigningTo: .quickPin) {
                self.cancelQuickPinShortcutRecording()
                self.presentHotkeyConflictAlert(conflict)
                return nil
            }

            Defaults.quickPinHotkeyKeyCode = Int(keyCode)
            Defaults.quickPinHotkeyModifiers = Int(carbonMods)
            self.finishQuickPinShortcutRecording()
            return nil
        }
    }

    @objc private func quickPinShortcutRestoreClicked() {
        if quickPinShortcutRecordingMonitor != nil {
            cancelQuickPinShortcutRecording()
        }
        Defaults.clearQuickPinHotkey()
        NotificationCenter.default.post(name: .hotkeyDidChange, object: nil)
        refreshQuickPinShortcutDisplay()
    }

    private func finishQuickPinShortcutRecording() {
        if let monitor = quickPinShortcutRecordingMonitor {
            NSEvent.removeMonitor(monitor)
            quickPinShortcutRecordingMonitor = nil
        }
        HotkeyManager.shared.endRecording()
        refreshQuickPinShortcutDisplay()
    }

    func cancelQuickPinShortcutRecording() {
        guard let monitor = quickPinShortcutRecordingMonitor else { return }
        NSEvent.removeMonitor(monitor)
        quickPinShortcutRecordingMonitor = nil
        HotkeyManager.shared.endRecording()
        refreshQuickPinShortcutDisplay()
    }

    private func refreshQuickPinShortcutDisplay() {
        quickPinShortcutSetButton?.title = L10n.shortcutSet
        if let display = HotkeyManager.currentQuickPinDisplayString() {
            quickPinShortcutField?.stringValue = display
            quickPinShortcutRestoreButton?.isHidden = false
        } else {
            quickPinShortcutField?.stringValue = L10n.quickPinShortcutDefaultDisplay
            quickPinShortcutRestoreButton?.isHidden = true
        }
    }

    @objc private func textRecognitionShortcutSetClicked() {
        if textRecognitionShortcutRecordingMonitor != nil {
            cancelTextRecognitionShortcutRecording()
            return
        }
        cancelShortcutRecordings(except: .textRecognition)
        HotkeyManager.shared.beginRecording()
        textRecognitionShortcutSetButton.title = L10n.shortcutCancel
        textRecognitionShortcutField.stringValue = L10n.shortcutWaiting
        textRecognitionShortcutRestoreButton.isHidden = true

        textRecognitionShortcutRecordingMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            let modifiers = event.modifierFlags
            let isEscape = event.keyCode == UInt16(kVK_Escape)
            let activeModifierMask: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
            let pressedModifiers = modifiers.intersection(activeModifierMask)

            if isEscape && pressedModifiers.isEmpty {
                self.cancelTextRecognitionShortcutRecording()
                return nil
            }

            var carbonMods: UInt32 = 0
            if modifiers.contains(.command) { carbonMods |= UInt32(cmdKey) }
            if modifiers.contains(.shift)   { carbonMods |= UInt32(shiftKey) }
            if modifiers.contains(.option)  { carbonMods |= UInt32(optionKey) }
            if modifiers.contains(.control) { carbonMods |= UInt32(controlKey) }
            let keyCode = UInt32(event.keyCode)

            if carbonMods == 0 && !HotkeyManager.isFunctionKey(keyCode) {
                self.cancelTextRecognitionShortcutRecording()
                self.presentShortcutNeedsModifierAlert()
                return nil
            }

            if let conflict = HotkeyManager.shared.hotkeyConflictMessage(
                forKeyCode: keyCode, modifiers: carbonMods, assigningTo: .textRecognition) {
                self.cancelTextRecognitionShortcutRecording()
                self.presentHotkeyConflictAlert(conflict)
                return nil
            }

            Defaults.textRecognitionHotkeyKeyCode = Int(keyCode)
            Defaults.textRecognitionHotkeyModifiers = Int(carbonMods)
            self.finishTextRecognitionShortcutRecording()
            return nil
        }
    }

    @objc private func textRecognitionShortcutRestoreClicked() {
        if textRecognitionShortcutRecordingMonitor != nil {
            cancelTextRecognitionShortcutRecording()
        }
        Defaults.clearTextRecognitionHotkey()
        NotificationCenter.default.post(name: .hotkeyDidChange, object: nil)
        refreshTextRecognitionShortcutDisplay()
    }

    private func finishTextRecognitionShortcutRecording() {
        if let m = textRecognitionShortcutRecordingMonitor {
            NSEvent.removeMonitor(m)
            textRecognitionShortcutRecordingMonitor = nil
        }
        HotkeyManager.shared.endRecording()
        refreshTextRecognitionShortcutDisplay()
    }

    func cancelTextRecognitionShortcutRecording() {
        guard textRecognitionShortcutRecordingMonitor != nil else { return }
        if let m = textRecognitionShortcutRecordingMonitor {
            NSEvent.removeMonitor(m)
            textRecognitionShortcutRecordingMonitor = nil
        }
        HotkeyManager.shared.endRecording()
        refreshTextRecognitionShortcutDisplay()
    }

    private func refreshTextRecognitionShortcutDisplay() {
        textRecognitionShortcutSetButton?.title = L10n.shortcutSet
        if let display = HotkeyManager.currentTextRecognitionDisplayString() {
            textRecognitionShortcutField?.stringValue = display
            textRecognitionShortcutRestoreButton?.isHidden = false
        } else {
            textRecognitionShortcutField?.stringValue = L10n.textRecognitionShortcutDefaultDisplay
            textRecognitionShortcutRestoreButton?.isHidden = true
        }
    }

    @objc private func copyImageTextShortcutSetClicked() {
        if copyImageTextShortcutRecordingMonitor != nil {
            cancelCopyImageTextShortcutRecording()
            return
        }
        cancelShortcutRecordings(except: .copyImageText)
        HotkeyManager.shared.beginRecording()
        copyImageTextShortcutSetButton.title = L10n.shortcutCancel
        copyImageTextShortcutField.stringValue = L10n.shortcutWaiting
        copyImageTextShortcutRestoreButton.isHidden = true

        copyImageTextShortcutRecordingMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            let modifiers = event.modifierFlags
            let isEscape = event.keyCode == UInt16(kVK_Escape)
            let activeModifierMask: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
            let pressedModifiers = modifiers.intersection(activeModifierMask)

            if isEscape && pressedModifiers.isEmpty {
                self.cancelCopyImageTextShortcutRecording()
                return nil
            }

            var carbonMods: UInt32 = 0
            if modifiers.contains(.command) { carbonMods |= UInt32(cmdKey) }
            if modifiers.contains(.shift)   { carbonMods |= UInt32(shiftKey) }
            if modifiers.contains(.option)  { carbonMods |= UInt32(optionKey) }
            if modifiers.contains(.control) { carbonMods |= UInt32(controlKey) }
            let keyCode = UInt32(event.keyCode)

            if carbonMods == 0 && !HotkeyManager.isFunctionKey(keyCode) {
                self.cancelCopyImageTextShortcutRecording()
                self.presentShortcutNeedsModifierAlert()
                return nil
            }

            if let conflict = HotkeyManager.shared.hotkeyConflictMessage(
                forKeyCode: keyCode, modifiers: carbonMods, assigningTo: .copyImageText) {
                self.cancelCopyImageTextShortcutRecording()
                self.presentHotkeyConflictAlert(conflict)
                return nil
            }

            Defaults.copyImageTextHotkeyKeyCode = Int(keyCode)
            Defaults.copyImageTextHotkeyModifiers = Int(carbonMods)
            self.finishCopyImageTextShortcutRecording()
            return nil
        }
    }

    @objc private func copyImageTextShortcutRestoreClicked() {
        if copyImageTextShortcutRecordingMonitor != nil {
            cancelCopyImageTextShortcutRecording()
        }
        Defaults.clearCopyImageTextHotkey()
        NotificationCenter.default.post(name: .hotkeyDidChange, object: nil)
        refreshCopyImageTextShortcutDisplay()
    }

    private func finishCopyImageTextShortcutRecording() {
        if let m = copyImageTextShortcutRecordingMonitor {
            NSEvent.removeMonitor(m)
            copyImageTextShortcutRecordingMonitor = nil
        }
        HotkeyManager.shared.endRecording()
        refreshCopyImageTextShortcutDisplay()
    }

    func cancelCopyImageTextShortcutRecording() {
        guard copyImageTextShortcutRecordingMonitor != nil else { return }
        if let m = copyImageTextShortcutRecordingMonitor {
            NSEvent.removeMonitor(m)
            copyImageTextShortcutRecordingMonitor = nil
        }
        HotkeyManager.shared.endRecording()
        refreshCopyImageTextShortcutDisplay()
    }

    private func refreshCopyImageTextShortcutDisplay() {
        copyImageTextShortcutSetButton?.title = L10n.shortcutSet
        if let display = HotkeyManager.currentCopyImageTextDisplayString() {
            copyImageTextShortcutField?.stringValue = display
            copyImageTextShortcutRestoreButton?.isHidden = false
        } else {
            copyImageTextShortcutField?.stringValue = L10n.copyImageTextShortcutDefaultDisplay
            copyImageTextShortcutRestoreButton?.isHidden = true
        }
    }

    @objc private func recordShortcutSetClicked() {
        if recordShortcutRecordingMonitor != nil {
            cancelRecordShortcutRecording()
            return
        }
        cancelShortcutRecordings(except: .record)
        HotkeyManager.shared.beginRecording()
        recordShortcutSetButton.title = L10n.shortcutCancel
        recordShortcutField.stringValue = L10n.shortcutWaiting
        recordShortcutRestoreButton.isHidden = true

        recordShortcutRecordingMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            let modifiers = event.modifierFlags
            let isEscape = event.keyCode == UInt16(kVK_Escape)
            let activeModifierMask: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
            let pressedModifiers = modifiers.intersection(activeModifierMask)

            if isEscape && pressedModifiers.isEmpty {
                self.cancelRecordShortcutRecording()
                return nil
            }

            var carbonMods: UInt32 = 0
            if modifiers.contains(.command) { carbonMods |= UInt32(cmdKey) }
            if modifiers.contains(.shift)   { carbonMods |= UInt32(shiftKey) }
            if modifiers.contains(.option)  { carbonMods |= UInt32(optionKey) }
            if modifiers.contains(.control) { carbonMods |= UInt32(controlKey) }
            let keyCode = UInt32(event.keyCode)

            if carbonMods == 0 && !HotkeyManager.isFunctionKey(keyCode) {
                self.cancelRecordShortcutRecording()
                self.presentShortcutNeedsModifierAlert()
                return nil
            }

            if let conflict = HotkeyManager.shared.hotkeyConflictMessage(
                forKeyCode: keyCode, modifiers: carbonMods, assigningTo: .record) {
                self.cancelRecordShortcutRecording()
                self.presentHotkeyConflictAlert(conflict)
                return nil
            }

            Defaults.recordHotkeyKeyCode = Int(keyCode)
            Defaults.recordHotkeyModifiers = Int(carbonMods)
            self.finishRecordShortcutRecording()
            return nil
        }
    }

    @objc private func recordShortcutRestoreClicked() {
        if recordShortcutRecordingMonitor != nil {
            cancelRecordShortcutRecording()
        }
        Defaults.clearRecordHotkey()
        NotificationCenter.default.post(name: .hotkeyDidChange, object: nil)
        refreshRecordShortcutDisplay()
    }

    private func finishRecordShortcutRecording() {
        if let m = recordShortcutRecordingMonitor {
            NSEvent.removeMonitor(m)
            recordShortcutRecordingMonitor = nil
        }
        HotkeyManager.shared.endRecording()
        refreshRecordShortcutDisplay()
    }

    func cancelRecordShortcutRecording() {
        guard recordShortcutRecordingMonitor != nil else { return }
        if let m = recordShortcutRecordingMonitor {
            NSEvent.removeMonitor(m)
            recordShortcutRecordingMonitor = nil
        }
        HotkeyManager.shared.endRecording()
        refreshRecordShortcutDisplay()
    }

    private func refreshRecordShortcutDisplay() {
        recordShortcutSetButton?.title = L10n.shortcutSet
        if let display = HotkeyManager.currentRecordDisplayString() {
            recordShortcutField?.stringValue = display
            recordShortcutRestoreButton?.isHidden = false
        } else {
            recordShortcutField?.stringValue = L10n.recordShortcutDefaultDisplay
            recordShortcutRestoreButton?.isHidden = true
        }
    }

    @objc private func clipboardShortcutSetClicked() {
        if clipboardShortcutRecordingMonitor != nil {
            cancelClipboardShortcutRecording()
            return
        }
        cancelShortcutRecordings(except: .clipboard)
        HotkeyManager.shared.beginRecording()
        clipboardShortcutSetButton.title = L10n.shortcutCancel
        clipboardShortcutField.stringValue = L10n.shortcutWaiting
        clipboardShortcutRestoreButton.isHidden = true

        clipboardShortcutRecordingMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            let modifiers = event.modifierFlags
            let isEscape = event.keyCode == UInt16(kVK_Escape)
            let activeModifierMask: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
            let pressedModifiers = modifiers.intersection(activeModifierMask)

            if isEscape && pressedModifiers.isEmpty {
                self.cancelClipboardShortcutRecording()
                return nil
            }

            var carbonMods: UInt32 = 0
            if modifiers.contains(.command) { carbonMods |= UInt32(cmdKey) }
            if modifiers.contains(.shift)   { carbonMods |= UInt32(shiftKey) }
            if modifiers.contains(.option)  { carbonMods |= UInt32(optionKey) }
            if modifiers.contains(.control) { carbonMods |= UInt32(controlKey) }
            let keyCode = UInt32(event.keyCode)

            // Unlike the screenshot/pin hotkeys, the editor hotkeys are
            // allowed to be bare — they only fire inside the editor overlay,
            // where typing is restricted to text-annotation editing (already
            // guarded against in the local key monitor).

            if let conflict = HotkeyManager.shared.hotkeyConflictMessage(
                forKeyCode: keyCode, modifiers: carbonMods, assigningTo: .clipboard) {
                self.cancelClipboardShortcutRecording()
                self.presentHotkeyConflictAlert(conflict)
                return nil
            }

            Defaults.clipboardHotkeyKeyCode = Int(keyCode)
            Defaults.clipboardHotkeyModifiers = Int(carbonMods)
            NotificationCenter.default.post(name: .hotkeyDidChange, object: nil)
            self.finishClipboardShortcutRecording()
            return nil
        }
    }

    @objc private func clipboardShortcutRestoreClicked() {
        if clipboardShortcutRecordingMonitor != nil {
            cancelClipboardShortcutRecording()
        }
        Defaults.clearClipboardHotkey()
        NotificationCenter.default.post(name: .hotkeyDidChange, object: nil)
        refreshClipboardShortcutDisplay()
    }

    private func finishClipboardShortcutRecording() {
        if let m = clipboardShortcutRecordingMonitor {
            NSEvent.removeMonitor(m)
            clipboardShortcutRecordingMonitor = nil
        }
        HotkeyManager.shared.endRecording()
        refreshClipboardShortcutDisplay()
    }

    func cancelClipboardShortcutRecording() {
        guard clipboardShortcutRecordingMonitor != nil else { return }
        if let m = clipboardShortcutRecordingMonitor {
            NSEvent.removeMonitor(m)
            clipboardShortcutRecordingMonitor = nil
        }
        HotkeyManager.shared.endRecording()
        refreshClipboardShortcutDisplay()
    }

    private func refreshClipboardShortcutDisplay() {
        clipboardShortcutSetButton?.title = L10n.shortcutSet
        if let display = HotkeyManager.currentClipboardDisplayString() {
            clipboardShortcutField?.stringValue = display
            clipboardShortcutRestoreButton?.isHidden = false
        } else {
            clipboardShortcutField?.stringValue = L10n.clipboardShortcutDefaultDisplay
            clipboardShortcutRestoreButton?.isHidden = true
        }
    }

    @objc private func fileSaveShortcutSetClicked() {
        if fileSaveShortcutRecordingMonitor != nil {
            cancelFileSaveShortcutRecording()
            return
        }
        cancelShortcutRecordings(except: .fileSave)
        HotkeyManager.shared.beginRecording()
        fileSaveShortcutSetButton.title = L10n.shortcutCancel
        fileSaveShortcutField.stringValue = L10n.shortcutWaiting
        fileSaveShortcutRestoreButton.isHidden = true

        fileSaveShortcutRecordingMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            let modifiers = event.modifierFlags
            let isEscape = event.keyCode == UInt16(kVK_Escape)
            let activeModifierMask: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
            let pressedModifiers = modifiers.intersection(activeModifierMask)

            if isEscape && pressedModifiers.isEmpty {
                self.cancelFileSaveShortcutRecording()
                return nil
            }

            var carbonMods: UInt32 = 0
            if modifiers.contains(.command) { carbonMods |= UInt32(cmdKey) }
            if modifiers.contains(.shift)   { carbonMods |= UInt32(shiftKey) }
            if modifiers.contains(.option)  { carbonMods |= UInt32(optionKey) }
            if modifiers.contains(.control) { carbonMods |= UInt32(controlKey) }
            let keyCode = UInt32(event.keyCode)

            if let conflict = HotkeyManager.shared.hotkeyConflictMessage(
                forKeyCode: keyCode, modifiers: carbonMods, assigningTo: .fileSave) {
                self.cancelFileSaveShortcutRecording()
                self.presentHotkeyConflictAlert(conflict)
                return nil
            }

            Defaults.fileSaveHotkeyKeyCode = Int(keyCode)
            Defaults.fileSaveHotkeyModifiers = Int(carbonMods)
            self.finishFileSaveShortcutRecording()
            return nil
        }
    }

    @objc private func fileSaveShortcutRestoreClicked() {
        if fileSaveShortcutRecordingMonitor != nil {
            cancelFileSaveShortcutRecording()
        }
        Defaults.clearFileSaveHotkey()
        refreshFileSaveShortcutDisplay()
    }

    private func finishFileSaveShortcutRecording() {
        if let m = fileSaveShortcutRecordingMonitor {
            NSEvent.removeMonitor(m)
            fileSaveShortcutRecordingMonitor = nil
        }
        HotkeyManager.shared.endRecording()
        refreshFileSaveShortcutDisplay()
    }

    func cancelFileSaveShortcutRecording() {
        guard fileSaveShortcutRecordingMonitor != nil else { return }
        if let m = fileSaveShortcutRecordingMonitor {
            NSEvent.removeMonitor(m)
            fileSaveShortcutRecordingMonitor = nil
        }
        HotkeyManager.shared.endRecording()
        refreshFileSaveShortcutDisplay()
    }

    private func refreshFileSaveShortcutDisplay() {
        fileSaveShortcutSetButton?.title = L10n.shortcutSet
        fileSaveShortcutField?.stringValue = HotkeyManager.currentFileSaveDisplayString()
        fileSaveShortcutRestoreButton?.isHidden = !Defaults.hasCustomFileSaveHotkey
    }

    @objc private func shortcutsResetClicked() {
        cancelShortcutRecording()
        cancelFullScreenScreenshotShortcutRecording()
        cancelColorPickerShortcutRecording()
        cancelQuickPinShortcutRecording()
        cancelTextRecognitionShortcutRecording()
        cancelCopyImageTextShortcutRecording()
        cancelRecordShortcutRecording()
        cancelClipboardShortcutRecording()
        cancelFileSaveShortcutRecording()

        Defaults.resetShortcutHotkeysToDefaults()
        NotificationCenter.default.post(name: .hotkeyDidChange, object: nil)
        refreshShortcutDisplay()
        refreshFullScreenScreenshotShortcutDisplay()
        refreshColorPickerShortcutDisplay()
        refreshQuickPinShortcutDisplay()
        refreshTextRecognitionShortcutDisplay()
        refreshCopyImageTextShortcutDisplay()
        refreshRecordShortcutDisplay()
        refreshClipboardShortcutDisplay()
        refreshFileSaveShortcutDisplay()
    }

    @objc private func updateLocalization() {
        permissionFlowController.setLocaleIdentifier(Defaults.language.lprojName)
        updateMicrophoneControlsEnabled()
        menuBarTitleLabel?.stringValue = L10n.showMenuBarIcon
        launchAtLoginTitleLabel?.stringValue = L10n.launchAtLogin
        pinAcrossSpacesTitleLabel?.stringValue = L10n.pinAcrossSpaces
        pinAcrossSpacesSubtitleLabel?.stringValue = L10n.pinAcrossSpacesHint
        pinAcrossSpacesSwitch?.state = Defaults.pinAcrossSpaces ? .on : .off
        langTitleLabel?.stringValue = L10n.languageHeader
        if let langPicker {
            langPicker.selectItem(at: AppLanguage.allCases.firstIndex(of: Defaults.language) ?? 0)
            langPicker.synchronizeTitleAndSelectedItem()
        }
        for (caption, tab) in zip(sectionCaptions, [SettingsTab.capture, .ocr]) {
            caption.text = tab == .capture ? L10n.settingsSectionCapture : L10n.settingsSectionSystem
        }
        filenameRuleCard?.refreshLocalization()
        screenshotQualityTitleLabel?.stringValue = L10n.screenshotQualityTitle
        screenshotQualitySubtitleLabel?.stringValue = L10n.screenshotQualitySubtitle
        screenshotQualityTitleLabel?.toolTip = L10n.screenshotQualitySubtitle
        screenshotQualitySaveTitleLabel?.stringValue = L10n.screenshotQualitySaveLabel
        screenshotQualityClipboardTitleLabel?.stringValue = L10n.screenshotQualityClipboardLabel
        refreshScreenshotQualityControls()
        savePathTitleLabel?.stringValue = L10n.savePathTitle
        savePathSubtitleLabel?.stringValue = L10n.savePathSubtitle
        savePathTitleLabel?.toolTip = L10n.savePathSubtitle
        askSaveLocationTitleLabel?.stringValue = L10n.askSaveLocationLabel
        askSaveLocationHintLabel?.stringValue = L10n.askSaveLocationHint
        askSaveLocationTitleLabel?.toolTip = L10n.askSaveLocationHint
        askSaveLocationSwitch?.toolTip = L10n.askSaveLocationHint
        askSaveLocationSwitch?.state = Defaults.askSaveLocation ? .on : .off
        autoRevealSavedFilesTitleLabel?.stringValue = L10n.autoRevealSavedFilesLabel
        autoRevealSavedFilesHintLabel?.stringValue = L10n.autoRevealSavedFilesHint
        autoRevealSavedFilesTitleLabel?.toolTip = L10n.autoRevealSavedFilesHint
        autoRevealSavedFilesSwitch?.toolTip = L10n.autoRevealSavedFilesHint
        autoRevealSavedFilesSwitch?.state = Defaults.autoRevealSavedFiles ? .on : .off
        recordingSavePathTitleLabel?.stringValue = L10n.recordingSavePathLabel
        recordingSaveFormatTitleLabel?.stringValue = L10n.recordingSaveFormatSettingLabel
        recordingSystemAudioTitleLabel?.stringValue = L10n.recordingSystemAudioLabel
        recordingSystemAudioHintLabel?.stringValue = L10n.recordingSystemAudioHint
        recordingMicrophoneTitleLabel?.stringValue = L10n.recordingMicrophoneLabel
        recordingMicrophoneHintLabel?.stringValue = L10n.recordingMicrophoneHint
        recordingSystemAudioSwitch?.state = Defaults.recordingSystemAudioEnabled ? .on : .off
        recordingMicrophoneSwitch?.state = Defaults.recordingMicrophoneEnabled ? .on : .off
        recordingMicrophoneDeviceTitleLabel?.stringValue = L10n.recordingMicrophoneDeviceLabel
        refreshMicrophoneDevicePopup()
        screenshotSavePathTitleLabel?.stringValue = L10n.screenshotSavePathLabel
        recordingSavePathChooseButton?.title = L10n.savePathChoose
        recordingSavePathRevealButton?.title = L10n.savePathReveal
        screenshotSavePathChooseButton?.title = L10n.savePathChoose
        screenshotSavePathRevealButton?.title = L10n.savePathReveal
        refreshSavePathControls()
        accessibilityNameLabel?.stringValue = L10n.accessibilityPermission
        accessibilityDescLabel?.stringValue = L10n.accessibilityDescription
        screenRecordingNameLabel?.stringValue = L10n.screenRecordingPermission
        screenRecordingDescLabel?.stringValue = L10n.screenRecordingDescription
        microphoneNameLabel?.stringValue = L10n.microphonePermission
        microphoneDescLabel?.stringValue = L10n.microphoneDescription
        historyCacheToggleTitleLabel?.stringValue = L10n.historyCacheToggleLabel
        historyCacheToggleHintLabel?.stringValue = L10n.historyCacheToggleHint
        clipboardTextCacheToggleTitleLabel?.stringValue = L10n.clipboardTextCacheToggleLabel
        clipboardTextCacheToggleHintLabel?.stringValue = L10n.clipboardTextCacheToggleHint
        clipboardTextHistoryLimitTitleLabel?.stringValue = L10n.clipboardTextHistoryLimitLabel
        historyCacheTitleLabel?.stringValue = L10n.historyCacheLabel
        historyPanelDisplayModeTitleLabel?.stringValue = L10n.historyPanelDisplayModeLabel
        historyPanelDisplayModeHintLabel?.stringValue = L10n.historyPanelDisplayModeHint
        historyPanelDialogModeTitleLabel?.stringValue = L10n.historyPanelDialogMode
        historyPanelDialogModeHintLabel?.stringValue = L10n.historyPanelDialogModeHint
        historyPanelNotchModeTitleLabel?.stringValue = L10n.historyPanelNotchMode
        historyPanelNotchModeHintLabel?.stringValue = L10n.historyPanelNotchModeHint
        historyNotchTriggerLabel?.stringValue = L10n.historyNotchTriggerLabel
        historyNotchTriggerPopup?.setAccessibilityLabel(L10n.historyNotchTriggerLabel)
        for (index, mode) in Defaults.HistoryNotchTriggerMode.allCases.enumerated() {
            historyNotchTriggerPopup?.item(at: index)?.title = mode.localizedTitle
        }
        windowShadowTitleLabel?.stringValue = L10n.windowShadowToggleLabel
        windowShadowSubtitleLabel?.stringValue = L10n.windowShadowToggleHint
        windowShadowSizeTitleLabel?.stringValue = L10n.shadowSizeLabel
        windowShadowSizeHintLabel?.stringValue = L10n.windowShadowSizeHint
        countdownTitleLabel?.stringValue = L10n.countdownLabel
        countdownHintLabel?.stringValue = L10n.countdownHint
        countdownValueLabel?.stringValue = "\(Defaults.countdownSeconds)\(L10n.countdownSecondsSuffix)"
        shortcutTitleLabel?.stringValue = L10n.shortcutHeader
        shortcutRestoreButton?.toolTip = L10n.shortcutRestore
        fullScreenScreenshotShortcutTitleLabel?.stringValue = L10n.fullScreenScreenshotShortcutHeader
        fullScreenScreenshotShortcutRestoreButton?.toolTip = L10n.shortcutRestore
        colorPickerShortcutTitleLabel?.stringValue = L10n.colorPickerShortcutHeader
        colorPickerShortcutRestoreButton?.toolTip = L10n.shortcutRestore
        quickPinShortcutTitleLabel?.stringValue = L10n.quickPinShortcutHeader
        quickPinShortcutRestoreButton?.toolTip = L10n.quickPinShortcutClear
        textRecognitionShortcutTitleLabel?.stringValue = L10n.textRecognitionShortcutHeader
        textRecognitionShortcutRestoreButton?.toolTip = L10n.shortcutRestore
        copyImageTextShortcutTitleLabel?.stringValue = L10n.copyImageTextShortcutHeader
        copyImageTextShortcutRestoreButton?.toolTip = L10n.shortcutRestore
        recordShortcutTitleLabel?.stringValue = L10n.recordShortcutHeader
        recordShortcutRestoreButton?.toolTip = L10n.shortcutRestore
        clipboardShortcutTitleLabel?.stringValue = L10n.clipboardShortcutHeader
        clipboardShortcutRestoreButton?.toolTip = L10n.shortcutRestore
        fileSaveShortcutTitleLabel?.stringValue = L10n.fileSaveShortcutHeader
        fileSaveShortcutRestoreButton?.toolTip = L10n.shortcutRestore
        shortcutResetButton?.title = L10n.toolbarSettingsReset
        aboutTaglineLabel?.stringValue = L10n.aboutTagline
        aboutLicenseTitleLabel?.stringValue = L10n.aboutLicense
        aboutSourceTitleLabel?.stringValue = L10n.aboutSourceCode
        aboutStarTitleLabel?.stringValue = L10n.aboutStarOnGitHub
        aboutFeatureRequestTitleLabel?.stringValue = L10n.aboutFeatureRequest
        aboutBugReportTitleLabel?.stringValue = L10n.aboutBugReport
        refreshShortcutDisplay()
        refreshFullScreenScreenshotShortcutDisplay()
        refreshColorPickerShortcutDisplay()
        refreshQuickPinShortcutDisplay()
        refreshTextRecognitionShortcutDisplay()
        refreshCopyImageTextShortcutDisplay()
        refreshRecordShortcutDisplay()
        refreshClipboardShortcutDisplay()
        refreshFileSaveShortcutDisplay()
        refreshBottomAction()
        accessibilityBadge?.refreshTitle()
        screenRecordingBadge?.refreshTitle()
        microphoneBadge?.refreshTitle()
        for btn in tabButtons { btn.refreshTitle() }
        detailTitleLabel?.stringValue = selectedTab.title
        window?.title = L10n.settingsTitle
    }
}

// MARK: - Flipped view (top-aligned scroll content)

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

// MARK: - Sidebar / detail panels

private final class SidebarPanel: NSView {
    private var gradientLayer: CAGradientLayer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        // The sidebar sits directly on the window's ink; nothing to draw.
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    override func layout() {
        super.layout()
        gradientLayer?.frame = bounds
    }
}

private final class DetailPanel: NSView {
    private var gradientLayer: CAGradientLayer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        // Content canvas: one step below the sidebar, hairline on the left.
        wantsLayer = true
        layer?.backgroundColor = Brand.canvas.cgColor
        let edge = CAGradientLayer()
        edge.colors = [Brand.line.cgColor, Brand.line.cgColor]
        layer?.addSublayer(edge)
        gradientLayer = edge
    }

    override func layout() {
        super.layout()
        gradientLayer?.frame = CGRect(x: 0, y: 0, width: 1, height: bounds.height)
    }

}

/// A hairline that fades to transparent at both edges of the sidebar.
private final class SidebarSeparatorView: NSView {
    private let gradient = CAGradientLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        gradient.colors = [
            NSColor.black.withAlphaComponent(0).cgColor,
            NSColor.black.withAlphaComponent(0.126).cgColor,
            NSColor.black.withAlphaComponent(0).cgColor,
        ]
        gradient.locations = [0, 0.5, 1]
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        layer?.addSublayer(gradient)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        let scale = window?.backingScaleFactor ?? 2
        let thickness = 1 / scale
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = CGRect(x: 0, y: (bounds.midY * scale).rounded() / scale,
                                width: bounds.width, height: thickness)
        CATransaction.commit()
    }
}

// MARK: - Sidebar tab button

private final class TabButton: NSControl {
    let tab: SettingsTab
    private let iconChip = NSView()
    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private var trackingArea: NSTrackingArea?
    private var isHovered = false

    var isSelected: Bool = false {
        didSet { applyAppearance() }
    }

    init(tab: SettingsTab) {
        self.tab = tab
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = Brand.radiusLarge
        layer?.cornerCurve = .continuous

        iconChip.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconChip)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = NSImage(systemSymbolName: tab.iconName, accessibilityDescription: nil)
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        iconView.imageScaling = .scaleProportionallyDown
        iconChip.addSubview(iconView)

        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        label.stringValue = tab.title
        addSubview(label)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 30),

            iconChip.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            iconChip.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconChip.widthAnchor.constraint(equalToConstant: 20),
            iconChip.heightAnchor.constraint(equalToConstant: 20),

            iconView.centerXAnchor.constraint(equalTo: iconChip.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconChip.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),

            label.leadingAnchor.constraint(equalTo: iconChip.trailingAnchor, constant: 8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
        ])

        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(tab.title)
        applyAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func refreshTitle() {
        label.stringValue = tab.title
        setAccessibilityLabel(tab.title)
    }

    private func applyAppearance() {
        if isSelected {
            layer?.backgroundColor = Brand.accent.cgColor
            label.textColor = Brand.onAccent
            iconView.contentTintColor = Brand.onAccent
        } else {
            layer?.backgroundColor = (
                isHovered ? Brand.subtleFill : NSColor.clear
            ).cgColor
            label.textColor = Brand.text
            iconView.contentTintColor = Brand.muted
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        trackingArea = area
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        applyAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        applyAppearance()
    }

    func refreshHoverAtCurrentMouseLocation() {
        guard let window else {
            if isHovered {
                isHovered = false
                applyAppearance()
            }
            return
        }
        let mouseLocation = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let shouldHighlight = visibleRect.contains(mouseLocation)
        guard isHovered != shouldHighlight else { return }
        isHovered = shouldHighlight
        applyAppearance()
    }

    override var acceptsFirstResponder: Bool { isEnabled }

    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        return sendAction(action, to: target)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == kVK_Space || event.keyCode == kVK_Return {
            _ = accessibilityPerformPress()
        } else {
            super.keyDown(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        sendAction(action, to: target)
    }

}

// MARK: - Action button (sidebar bottom row, mirrors TabButton's chrome)

private final class ActionButton: NSControl {
    private let iconChip = NSView()
    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private var trackingArea: NSTrackingArea?
    private var tint: NSColor = Brand.accent
    private var prominent = false

    init(symbolName: String, title: String, tint: NSColor) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = Brand.radiusLarge
        layer?.cornerCurve = .continuous

        iconChip.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconChip)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        iconView.imageScaling = .scaleProportionallyDown
        iconChip.addSubview(iconView)

        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        addSubview(label)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 32),

            iconChip.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            iconChip.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconChip.widthAnchor.constraint(equalToConstant: 20),
            iconChip.heightAnchor.constraint(equalToConstant: 20),

            iconView.centerXAnchor.constraint(equalTo: iconChip.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconChip.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),

            label.leadingAnchor.constraint(equalTo: iconChip.trailingAnchor, constant: 8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
        ])

        update(symbolName: symbolName, title: title, tint: tint)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(symbolName: String, title: String, tint: NSColor, prominent: Bool = false) {
        self.tint = tint
        self.prominent = prominent
        iconView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
        label.stringValue = title
        applyAppearance()
    }

    override var isEnabled: Bool {
        didSet { alphaValue = isEnabled ? 1.0 : 0.45 }
    }

    private func applyAppearance() {
        if prominent {
            layer?.backgroundColor = tint.cgColor
            iconView.contentTintColor = Brand.onAccent
            label.textColor = Brand.onAccent
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
            iconView.contentTintColor = tint
            label.textColor = tint
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        trackingArea = area
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        guard isEnabled else { return }
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.035).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.07).cgColor
        sendAction(action, to: target)
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.035).cgColor
    }

    override var acceptsFirstResponder: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if isEnabled, event.charactersIgnoringModifiers == "\r" {
            sendAction(action, to: target)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

// MARK: - Settings tick slider

private final class SettingsTickSlider: NSControl {
    var minValue: Double
    var maxValue: Double
    var stepValue: Double
    var numberOfTickMarks: Int

    override var doubleValue: Double {
        get { value }
        set { setValue(newValue, notify: false) }
    }

    override var isEnabled: Bool {
        didSet {
            if !isEnabled {
                isDragging = false
            }
            needsDisplay = true
        }
    }

    private var value: Double
    private var isDragging = false {
        didSet { needsDisplay = true }
    }

    private let knobSize = NSSize(width: 9, height: 18)
    private let trackHeight: CGFloat = 3.5
    private let tickDiameter: CGFloat = 2.5
    private let tickGap: CGFloat = 5
    private let accentColor = Brand.accent

    init(
        frame: NSRect = .zero,
        value: Double,
        minValue: Double,
        maxValue: Double,
        stepValue: Double,
        numberOfTickMarks: Int,
        target: AnyObject?,
        action: Selector?
    ) {
        self.minValue = minValue
        self.maxValue = maxValue
        self.stepValue = stepValue
        self.numberOfTickMarks = max(0, numberOfTickMarks)
        self.value = Self.normalizedValue(
            value,
            minValue: minValue,
            maxValue: maxValue,
            stepValue: stepValue
        )
        super.init(frame: frame)
        self.target = target
        self.action = action
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 22)
    }

    override var acceptsFirstResponder: Bool { isEnabled }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { isEnabled }

    override func draw(_ dirtyRect: NSRect) {
        let enabledAlpha: CGFloat = isEnabled ? 1 : 0.35
        let trackRect = NSRect(
            x: 0,
            y: floor(bounds.midY - trackHeight / 2),
            width: bounds.width,
            height: trackHeight
        )
        let travelRect = NSRect(
            x: knobSize.width / 2,
            y: trackRect.minY,
            width: max(1, bounds.width - knobSize.width),
            height: trackRect.height
        )

        let trackPath = NSBezierPath(
            roundedRect: trackRect,
            xRadius: trackHeight / 2,
            yRadius: trackHeight / 2
        )
        NSColor.black.withAlphaComponent(0.10 * enabledAlpha).setFill()
        trackPath.fill()

        let knobCenterX = travelRect.minX + normalizedFraction * travelRect.width
        let fillRect = NSRect(
            x: trackRect.minX,
            y: trackRect.minY,
            width: max(0, knobCenterX - trackRect.minX),
            height: trackRect.height
        )
        if fillRect.width > 0 {
            let fillPath = NSBezierPath(
                roundedRect: fillRect,
                xRadius: trackHeight / 2,
                yRadius: trackHeight / 2
            )
            accentColor.withAlphaComponent(enabledAlpha).setFill()
            fillPath.fill()
        }

        drawKnob(centerX: knobCenterX, enabledAlpha: enabledAlpha)
        drawTickMarks(in: travelRect, enabledAlpha: enabledAlpha)
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        window?.makeFirstResponder(self)
        isDragging = true
        updateValue(with: event, notify: true)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isEnabled else { return }
        updateValue(with: event, notify: true)
    }

    override func mouseUp(with event: NSEvent) {
        guard isEnabled else {
            isDragging = false
            return
        }
        updateValue(with: event, notify: true)
        isDragging = false
    }

    override func keyDown(with event: NSEvent) {
        guard isEnabled else { return }
        let step = stepValue > 0 ? stepValue : (maxValue - minValue) / 10
        switch Int(event.keyCode) {
        case kVK_LeftArrow, kVK_DownArrow:
            setValue(value - step, notify: true)
        case kVK_RightArrow, kVK_UpArrow:
            setValue(value + step, notify: true)
        default:
            super.keyDown(with: event)
        }
    }

    private var normalizedFraction: CGFloat {
        guard maxValue > minValue else { return 0 }
        return CGFloat((value - minValue) / (maxValue - minValue))
    }

    private func drawTickMarks(in trackRect: NSRect, enabledAlpha: CGFloat) {
        guard numberOfTickMarks > 1 else { return }
        let dotY = trackRect.minY - tickGap - tickDiameter
        for index in 0..<numberOfTickMarks {
            let fraction = CGFloat(index) / CGFloat(numberOfTickMarks - 1)
            let x = trackRect.minX + fraction * trackRect.width
            let tickRect = NSRect(
                x: x - tickDiameter / 2,
                y: dotY,
                width: tickDiameter,
                height: tickDiameter
            )
            NSColor.black.withAlphaComponent(0.168 * enabledAlpha).setFill()
            NSBezierPath(ovalIn: tickRect).fill()
        }
    }

    private func drawKnob(centerX: CGFloat, enabledAlpha: CGFloat) {
        let knobRect = NSRect(
            x: centerX - knobSize.width / 2,
            y: bounds.midY - knobSize.height / 2,
            width: knobSize.width,
            height: knobSize.height
        )
        let knobPath = NSBezierPath(
            roundedRect: knobRect,
            xRadius: knobSize.width / 2,
            yRadius: knobSize.width / 2
        )

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.18 * enabledAlpha)
        shadow.shadowBlurRadius = 1.5
        shadow.shadowOffset = NSSize(width: 0, height: -0.5)
        shadow.set()
        NSColor(white: isDragging ? 0.97 : 1.0, alpha: enabledAlpha).setFill()
        knobPath.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSColor.black.withAlphaComponent(0.18 * enabledAlpha).setStroke()
        knobPath.lineWidth = 0.5
        knobPath.stroke()
    }

    private func updateValue(with event: NSEvent, notify: Bool) {
        guard bounds.width > knobSize.width else { return }
        let location = convert(event.locationInWindow, from: nil)
        let trackMinX = knobSize.width / 2
        let trackWidth = max(1, bounds.width - knobSize.width)
        let fraction = min(max((location.x - trackMinX) / trackWidth, 0), 1)
        let newValue = minValue + Double(fraction) * (maxValue - minValue)
        setValue(newValue, notify: notify)
    }

    private func setValue(_ newValue: Double, notify: Bool) {
        let normalized = Self.normalizedValue(
            newValue,
            minValue: minValue,
            maxValue: maxValue,
            stepValue: stepValue
        )
        value = normalized
        needsDisplay = true
        if notify {
            sendAction(action, to: target)
        }
    }

    private static func normalizedValue(
        _ rawValue: Double,
        minValue: Double,
        maxValue: Double,
        stepValue: Double
    ) -> Double {
        let clamped = min(max(rawValue, minValue), maxValue)
        guard stepValue > 0 else { return clamped }
        let steps = ((clamped - minValue) / stepValue).rounded()
        let snapped = minValue + steps * stepValue
        return min(max(snapped, minValue), maxValue)
    }
}

// MARK: - Card view

/// Live preview of the window-capture shadow: a small window-like card
/// floating on a desktop-like backdrop. The shadow scales with `shadowSize`
/// so the user sees how high the captured window will appear to float.
private final class ShadowPreviewView: NSView {
    var shadowSize: CGFloat = 22 { didSet { needsDisplay = true } }
    var isEffectEnabled: Bool = true { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let backdrop = NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8)
        backdrop.addClip()

        // Desktop-like light backdrop so the dark shadow stays visible
        // (the settings UI itself is dark).
        let gradient = NSGradient(colors: [
            NSColor(calibratedRed: 0.74, green: 0.78, blue: 0.85, alpha: 1),
            NSColor(calibratedRed: 0.60, green: 0.64, blue: 0.72, alpha: 1)
        ])
        gradient?.draw(in: bounds, angle: -90)

        // Window card geometry, centered; floats higher as the shadow grows.
        let cardW = min(bounds.width * 0.56, 210)
        let cardH: CGFloat = 64
        let lift = isEffectEnabled ? min(shadowSize, 60) * 0.10 : 0
        let cardRect = NSRect(
            x: ((bounds.width - cardW) / 2).rounded(),
            y: ((bounds.height - cardH) / 2 + lift).rounded(),
            width: cardW,
            height: cardH
        )
        let radius: CGFloat = 9
        let cardPath = NSBezierPath(roundedRect: cardRect, xRadius: radius, yRadius: radius)

        guard let ctx = NSGraphicsContext.current else { return }

        // Shadow pass. Scaled down relative to the real export — the preview
        // card is tiny — but proportional, so the slider's effect reads.
        ctx.saveGraphicsState()
        if isEffectEnabled, shadowSize > 0 {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.42)
            shadow.shadowBlurRadius = shadowSize * 0.62
            shadow.shadowOffset = NSSize(width: 0, height: -shadowSize * 0.30)
            shadow.set()
        }
        NSColor.white.setFill()
        cardPath.fill()
        ctx.restoreGraphicsState()

        // Title-bar strip + traffic-light dots, clipped to the card.
        ctx.saveGraphicsState()
        cardPath.addClip()
        NSColor(calibratedWhite: 0.93, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(
            x: cardRect.minX, y: cardRect.maxY - 16,
            width: cardRect.width, height: 16
        )).fill()
        let dotColors: [NSColor] = [
            NSColor(calibratedRed: 1.00, green: 0.37, blue: 0.35, alpha: 1),
            NSColor(calibratedRed: 1.00, green: 0.74, blue: 0.18, alpha: 1),
            NSColor(calibratedRed: 0.31, green: 0.79, blue: 0.31, alpha: 1)
        ]
        for (i, color) in dotColors.enumerated() {
            color.setFill()
            let d: CGFloat = 7
            NSBezierPath(ovalIn: NSRect(
                x: cardRect.minX + 9 + CGFloat(i) * 12,
                y: cardRect.maxY - 11.5, width: d, height: d
            )).fill()
        }
        ctx.restoreGraphicsState()

        // Hairline border for crispness.
        NSColor.black.withAlphaComponent(0.08).setStroke()
        cardPath.lineWidth = 1
        cardPath.stroke()
    }
}

private final class HistoryPanelModePreviewView: NSView {
    var mode: HistoryPanelSettingsMode {
        didSet { needsDisplay = true }
    }

    var isEffectEnabled: Bool = true {
        didSet { needsDisplay = true }
    }

    private let accentBlue = Brand.accent
    private let surfaceColor = NSColor.white

    init(mode: HistoryPanelSettingsMode) {
        self.mode = mode
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current else { return }

        let rect = bounds
        let backdrop = NSBezierPath(roundedRect: rect, xRadius: 16, yRadius: 16)
        ctx.saveGraphicsState()
        backdrop.addClip()

        NSColor(calibratedRed: 0.86, green: 0.87, blue: 0.90, alpha: 1).setFill()
        backdrop.fill()
        ctx.cgContext.setAlpha(isEffectEnabled ? 1 : 0.42)
        switch mode {
        case .dialog:
            drawDialogPreview(in: rect.insetBy(dx: 24, dy: 18))
        case .notch:
            drawNotchPreview(in: rect.insetBy(dx: 24, dy: 0))
        }
        ctx.restoreGraphicsState()

        NSColor.white.withAlphaComponent(isEffectEnabled ? 0.08 : 0.04).setStroke()
        backdrop.lineWidth = 1
        backdrop.stroke()
    }

    private func drawDialogPreview(in rect: NSRect) {
        let panelWidth = min(rect.width * 0.82, 560)
        let panelHeight = min(rect.height - 14, 86)
        let panelRect = NSRect(
            x: rect.midX - panelWidth / 2,
            y: rect.midY - panelHeight / 2 - 6,
            width: panelWidth,
            height: panelHeight
        )
        drawFloatingSurface(in: panelRect, radius: 18, shadow: true)
        drawToolbarLine(in: panelRect)
        drawTileRow(in: panelRect.insetBy(dx: 18, dy: 16), count: 4)
    }

    private func drawNotchPreview(in rect: NSRect) {
        let panelWidth = min(rect.width * 0.88, 620)
        let panelHeight = min(rect.height * 0.78, 106)
        let panelRect = NSRect(
            x: rect.midX - panelWidth / 2,
            y: rect.maxY - panelHeight,
            width: panelWidth,
            height: panelHeight
        )

        drawTopAttachedSurface(in: panelRect)

        drawToolbarLine(in: panelRect, leadingInset: 36)
        drawTileRow(in: panelRect.insetBy(dx: 34, dy: 16), count: 5)
    }

    private func drawFloatingSurface(in rect: NSRect, radius: CGFloat, shadow: Bool) {
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

        guard let ctx = NSGraphicsContext.current else { return }
        ctx.saveGraphicsState()
        if shadow {
            let panelShadow = NSShadow()
            panelShadow.shadowColor = NSColor.black.withAlphaComponent(0.34)
            panelShadow.shadowBlurRadius = 18
            panelShadow.shadowOffset = NSSize(width: 0, height: -6)
            panelShadow.set()
        }
        surfaceColor.withAlphaComponent(0.96).setFill()
        path.fill()
        ctx.restoreGraphicsState()

        NSColor.black.withAlphaComponent(0.08).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    private func drawTopAttachedSurface(in rect: NSRect) {
        let path = notchPath(in: rect, flare: 14, bottomRadius: 18)
        surfaceColor.withAlphaComponent(0.96).setFill()
        path.fill()

        NSColor.black.withAlphaComponent(0.08).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    private func drawToolbarLine(in panelRect: NSRect, leadingInset: CGFloat = 18) {
        let y = panelRect.maxY - 22
        let active = NSRect(x: panelRect.minX + leadingInset, y: y, width: 46, height: 10)
        accentBlue.setFill()
        NSBezierPath(roundedRect: active, xRadius: 5, yRadius: 5).fill()

        var x = active.maxX + 10
        for _ in 0..<3 {
            let pill = NSRect(x: x, y: y, width: 34, height: 10)
            NSColor.black.withAlphaComponent(0.112).setFill()
            NSBezierPath(roundedRect: pill, xRadius: 5, yRadius: 5).fill()
            x += 44
        }
    }

    private func drawTileRow(in rect: NSRect, count: Int) {
        let contentRect = NSRect(
            x: rect.minX,
            y: rect.minY,
            width: rect.width,
            height: max(28, rect.height - 28)
        )
        let gap: CGFloat = 10
        let tileWidth = max(34, (contentRect.width - gap * CGFloat(count - 1)) / CGFloat(count))
        for index in 0..<count {
            let tileRect = NSRect(
                x: contentRect.minX + CGFloat(index) * (tileWidth + gap),
                y: contentRect.minY,
                width: tileWidth,
                height: contentRect.height
            )
            NSColor.black.withAlphaComponent(0.07).setFill()
            NSBezierPath(roundedRect: tileRect, xRadius: 8, yRadius: 8).fill()

            let bar = NSRect(
                x: tileRect.minX + 8,
                y: tileRect.midY - 4,
                width: max(18, tileRect.width - 16),
                height: 8
            )
            (index == 0 ? accentBlue : NSColor.black.withAlphaComponent(0.168)).setFill()
            NSBezierPath(roundedRect: bar, xRadius: 4, yRadius: 4).fill()
        }
    }

    private func notchPath(in rect: NSRect, flare: CGFloat, bottomRadius: CGFloat) -> NSBezierPath {
        let flare = max(0, min(flare, rect.width * 0.25, rect.height))
        let bodyLeft = rect.minX + flare
        let bodyRight = rect.maxX - flare
        let bottom = max(0, min(bottomRadius, (bodyRight - bodyLeft) * 0.5, rect.height))
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.minX, y: rect.maxY))
        path.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
        path.curve(
            to: NSPoint(x: bodyRight, y: rect.maxY - flare),
            controlPoint1: NSPoint(x: rect.maxX - flare * 0.5, y: rect.maxY),
            controlPoint2: NSPoint(x: bodyRight, y: rect.maxY - flare * 0.5)
        )
        path.line(to: NSPoint(x: bodyRight, y: rect.minY + bottom))
        path.curve(
            to: NSPoint(x: bodyRight - bottom, y: rect.minY),
            controlPoint1: NSPoint(x: bodyRight, y: rect.minY + bottom * 0.45),
            controlPoint2: NSPoint(x: bodyRight - bottom * 0.45, y: rect.minY)
        )
        path.line(to: NSPoint(x: bodyLeft + bottom, y: rect.minY))
        path.curve(
            to: NSPoint(x: bodyLeft, y: rect.minY + bottom),
            controlPoint1: NSPoint(x: bodyLeft + bottom * 0.45, y: rect.minY),
            controlPoint2: NSPoint(x: bodyLeft, y: rect.minY + bottom * 0.45)
        )
        path.line(to: NSPoint(x: bodyLeft, y: rect.maxY - flare))
        path.curve(
            to: NSPoint(x: rect.minX, y: rect.maxY),
            controlPoint1: NSPoint(x: bodyLeft, y: rect.maxY - flare * 0.5),
            controlPoint2: NSPoint(x: rect.minX + flare * 0.5, y: rect.maxY)
        )
        path.close()
        return path
    }

}

private final class HistoryPanelModeOptionView: NSControl {
    let mode: HistoryPanelSettingsMode
    let title: NSTextField
    let subtitle: NSTextField

    var isSelected: Bool = false {
        didSet { applyAppearance() }
    }

    override var isEnabled: Bool {
        didSet { applyAppearance() }
    }

    private let checkView = NSImageView()
    private var trackingArea: NSTrackingArea?
    private var isHovered = false {
        didSet { applyAppearance() }
    }

    private let accentBlue = Brand.accent

    init(mode: HistoryPanelSettingsMode, title: String, subtitle: String) {
        self.mode = mode
        self.title = NSTextField(labelWithString: title)
        self.subtitle = NSTextField(wrappingLabelWithString: subtitle)
        super.init(frame: .zero)
        commonInit()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func commonInit() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 13
        layer?.cornerCurve = .continuous

        title.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        title.isEditable = false
        title.isSelectable = false
        title.refusesFirstResponder = true
        title.translatesAutoresizingMaskIntoConstraints = false
        addSubview(title)

        subtitle.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        subtitle.isEditable = false
        subtitle.isSelectable = false
        subtitle.refusesFirstResponder = true
        subtitle.lineBreakMode = .byWordWrapping
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        addSubview(subtitle)

        checkView.translatesAutoresizingMaskIntoConstraints = false
        checkView.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
        checkView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        checkView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(checkView)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 92),

            checkView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            checkView.topAnchor.constraint(equalTo: topAnchor, constant: 18),
            checkView.widthAnchor.constraint(equalToConstant: 18),
            checkView.heightAnchor.constraint(equalToConstant: 18),

            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            title.topAnchor.constraint(equalTo: topAnchor, constant: 18),
            title.trailingAnchor.constraint(lessThanOrEqualTo: checkView.leadingAnchor, constant: -8),

            subtitle.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 4),
            subtitle.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            subtitle.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
        ])

        setContentCompressionResistancePriority(.required, for: .vertical)
        applyAppearance()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let result = super.hitTest(point)
        guard let result else { return nil }
        return result === self ? result : self
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        trackingArea = area
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        guard isEnabled else { return }
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        sendAction(action, to: target)
    }

    override var acceptsFirstResponder: Bool { isEnabled }

    override func keyDown(with event: NSEvent) {
        guard isEnabled else { return }
        let keyCode = Int(event.keyCode)
        if keyCode == kVK_Space || keyCode == kVK_Return {
            sendAction(action, to: target)
        } else {
            super.keyDown(with: event)
        }
    }

    private func applyAppearance() {
        let enabledAlpha: CGFloat = isEnabled ? 1 : 0.42
        let backgroundAlpha: CGFloat
        if isSelected {
            backgroundAlpha = 0.052
        } else if isHovered {
            backgroundAlpha = 0.044
        } else {
            backgroundAlpha = 0.018
        }

        layer?.backgroundColor = NSColor.white.withAlphaComponent(backgroundAlpha * enabledAlpha).cgColor
        layer?.borderColor = (isSelected ? accentBlue : NSColor.black.withAlphaComponent(0.063 * enabledAlpha)).cgColor
        layer?.borderWidth = isSelected ? 2 : 1

        title.textColor = Brand.text.withAlphaComponent(isEnabled ? 0.94 : 0.4)
        subtitle.textColor = Brand.text.withAlphaComponent(isEnabled ? 0.58 : 0.35)
        checkView.isHidden = !isSelected
        checkView.contentTintColor = accentBlue.withAlphaComponent(enabledAlpha)
    }
}

private final class CardView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }
    private func commonInit() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = Brand.surfaceRaised.cgColor
        layer?.borderColor = NSColor.black.withAlphaComponent(0.042).cgColor
        layer?.borderWidth = 1
    }
}

/// Small muted caption that groups sidebar entries, like System Settings.
private final class SidebarSectionCaption: NSView {
    private let label = NSTextField(labelWithString: "")
    var text: String {
        get { label.stringValue }
        set { label.stringValue = newValue }
    }

    init(text: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        label.textColor = Brand.muted
        label.stringValue = text
        addSubview(label)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 30),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
        ])
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setText(_ text: String) { label.stringValue = text }
}

// MARK: - Status badge

final class StatusBadge: NSView {
    private let label = NSTextField(labelWithString: "")
    private var granted: Bool = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.cornerCurve = .continuous
        label.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
        ])
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    func configure(granted: Bool) {
        self.granted = granted
        refreshTitle()
    }

    func refreshTitle() {
        let color: NSColor = granted ? .systemGreen : .systemOrange
        label.stringValue = granted ? L10n.permissionGranted : L10n.permissionNotGranted
        label.textColor = color
        layer?.backgroundColor = color.withAlphaComponent(0.18).cgColor
    }
}

// MARK: - Hover button (clickable permission row)

private final class HoverButton: NSButton {
    var cornerRadius: CGFloat = 10 {
        didSet { layer?.cornerRadius = cornerRadius }
    }
    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = NSColor.clear.cgColor
        (cell as? NSButtonCell)?.highlightsBy = []
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        trackingArea = area
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.042).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    override func mouseDown(with event: NSEvent) {
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.07).cgColor
        super.mouseDown(with: event)
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.042).cgColor
    }
}
