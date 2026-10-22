import AppKit
import Carbon

/// Which toolbar a grid section maps to in `ToolbarLayout`.
enum ToolbarSection {
    case primary
    case side
    case hidden
}

/// Settings tab for customizing the editor toolbars. Shows a live preview of
/// the editor with the current layout, plus three drag-and-drop grids for
/// assigning tools to the main toolbar, the side toolbar, or hiding them.
final class ToolbarSettingsPane: NSView {
    /// Layout currently shown in the grids and preview. Drag edits persist
    /// immediately, so the settings page has no separate apply step.
    private var workingLayout: ToolbarLayout = Defaults.toolbarLayout.normalized()

    private let preview = ToolbarLayoutPreviewView()
    private var previewHeightConstraint: NSLayoutConstraint!
    private var primaryGrid: ToolbarSlotGridView!
    private var sideGrid: ToolbarSlotGridView!
    private var hiddenGrid: ToolbarSlotGridView!

    private let primaryTitle = ToolbarSettingsPane.sectionTitleLabel()
    private let primaryHint = ToolbarSettingsPane.hintLabel()
    private let sideTitle = ToolbarSettingsPane.sectionTitleLabel()
    private let sideHint = ToolbarSettingsPane.hintLabel()
    private let hiddenTitle = ToolbarSettingsPane.sectionTitleLabel()
    private let hiddenHint = ToolbarSettingsPane.hintLabel()
    private let footnote = ToolbarSettingsPane.hintLabel()
    private let shortcutHint = ToolbarSettingsPane.hintLabel()
    private let additionalShortcutsTitle = ToolbarSettingsPane.sectionTitleLabel()
    private let selectShortcutButton = EditorShortcutActionButton(action: .select)
    private let shapeFillShortcutButton = EditorShortcutActionButton(action: .shapeFill)
    private let shortcutResetButton = NSButton()
    private let resetButton = NSButton()
    private var recordingAction: EditorShortcutAction?
    private var shortcutRecordingMonitor: Any?

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        buildUI()
        syncFromWorkingLayout()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onLanguageChanged),
            name: .languageDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onShortcutsChanged),
            name: .editorShortcutsDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onShortcutsChanged),
            name: .hotkeyDidChange,
            object: nil
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        cancelShortcutRecording()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Build

    private func buildUI() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        // Preview card.
        let previewCard = Self.makeCard()
        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.setContentCompressionResistancePriority(.required, for: .vertical)
        preview.setContentHuggingPriority(.required, for: .vertical)
        previewCard.addSubview(preview)
        previewHeightConstraint = preview.heightAnchor.constraint(equalToConstant: preview.preferredHeight)
        NSLayoutConstraint.activate([
            preview.topAnchor.constraint(equalTo: previewCard.topAnchor, constant: 14),
            preview.leadingAnchor.constraint(equalTo: previewCard.leadingAnchor, constant: 14),
            preview.trailingAnchor.constraint(equalTo: previewCard.trailingAnchor, constant: -14),
            preview.bottomAnchor.constraint(equalTo: previewCard.bottomAnchor, constant: -14),
            previewHeightConstraint,
        ])
        stack.addArrangedSubview(previewCard)
        previewCard.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        // Sections card — the three drag grids.
        primaryGrid = ToolbarSlotGridView(section: .primary)
        sideGrid = ToolbarSlotGridView(section: .side)
        hiddenGrid = ToolbarSlotGridView(section: .hidden)
        for grid in [primaryGrid, sideGrid, hiddenGrid] {
            grid?.onLayoutChanged = { [weak self] in self?.collectWorkingLayout() }
            grid?.onShortcutEdit = { [weak self] item in
                self?.beginShortcutRecording(for: .toolbar(item))
            }
            grid?.onShortcutContextMenu = { [weak self] item, view, event in
                self?.showShortcutContextMenu(for: .toolbar(item), from: view, event: event)
            }
            grid?.gridProvider = { [weak self] in
                [self?.primaryGrid, self?.sideGrid, self?.hiddenGrid].compactMap { $0 }
            }
        }

        let sectionsCard = Self.makeCard()
        let sectionsStack = NSStackView()
        sectionsStack.orientation = .vertical
        sectionsStack.alignment = .leading
        sectionsStack.spacing = 8
        sectionsStack.translatesAutoresizingMaskIntoConstraints = false
        sectionsCard.addSubview(sectionsStack)
        NSLayoutConstraint.activate([
            sectionsStack.topAnchor.constraint(equalTo: sectionsCard.topAnchor, constant: 16),
            sectionsStack.leadingAnchor.constraint(equalTo: sectionsCard.leadingAnchor, constant: 16),
            sectionsStack.trailingAnchor.constraint(equalTo: sectionsCard.trailingAnchor, constant: -16),
            sectionsStack.bottomAnchor.constraint(equalTo: sectionsCard.bottomAnchor, constant: -16),
        ])

        addSection(to: sectionsStack, title: primaryTitle, hint: primaryHint, grid: primaryGrid)
        addSection(to: sectionsStack, title: sideTitle, hint: sideHint, grid: sideGrid)
        addSection(to: sectionsStack, title: hiddenTitle, hint: hiddenHint, grid: hiddenGrid)

        footnote.lineBreakMode = .byWordWrapping
        footnote.maximumNumberOfLines = 2
        sectionsStack.setCustomSpacing(14, after: hiddenGrid)
        sectionsStack.addArrangedSubview(footnote)
        footnote.widthAnchor.constraint(equalTo: sectionsStack.widthAnchor).isActive = true

        shortcutHint.lineBreakMode = .byWordWrapping
        shortcutHint.maximumNumberOfLines = 2
        sectionsStack.setCustomSpacing(8, after: footnote)
        sectionsStack.addArrangedSubview(shortcutHint)
        shortcutHint.widthAnchor.constraint(equalTo: sectionsStack.widthAnchor).isActive = true

        sectionsStack.setCustomSpacing(16, after: shortcutHint)
        sectionsStack.addArrangedSubview(additionalShortcutsTitle)
        let additionalRow = NSStackView(views: [selectShortcutButton, shapeFillShortcutButton])
        additionalRow.orientation = .horizontal
        additionalRow.alignment = .centerY
        additionalRow.distribution = .fillEqually
        additionalRow.spacing = 8
        additionalRow.translatesAutoresizingMaskIntoConstraints = false
        sectionsStack.setCustomSpacing(8, after: additionalShortcutsTitle)
        sectionsStack.addArrangedSubview(additionalRow)
        additionalRow.widthAnchor.constraint(equalTo: sectionsStack.widthAnchor).isActive = true

        for button in [selectShortcutButton, shapeFillShortcutButton] {
            button.onActivate = { [weak self] action in
                self?.beginShortcutRecording(for: action)
            }
            button.onContextMenu = { [weak self] action, view, event in
                self?.showShortcutContextMenu(for: action, from: view, event: event)
            }
        }

        stack.addArrangedSubview(sectionsCard)
        sectionsCard.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        // Footer: reset lives at the lower-right. Drag changes apply instantly.
        let footer = NSStackView()
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 10
        footer.translatesAutoresizingMaskIntoConstraints = false

        Self.styleButton(resetButton, title: "", prominent: false)
        resetButton.target = self
        resetButton.action = #selector(resetTapped)

        Self.styleButton(shortcutResetButton, title: "", prominent: false)
        shortcutResetButton.target = self
        shortcutResetButton.action = #selector(resetShortcutsTapped)

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        footer.addArrangedSubview(spacer)
        footer.addArrangedSubview(shortcutResetButton)
        footer.addArrangedSubview(resetButton)

        stack.addArrangedSubview(footer)
        footer.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -22),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -22),
        ])

        applyLocalizedStrings()
    }

    private func addSection(
        to stack: NSStackView,
        title: NSTextField,
        hint: NSTextField,
        grid: ToolbarSlotGridView
    ) {
        hint.lineBreakMode = .byWordWrapping
        hint.maximumNumberOfLines = 2
        stack.addArrangedSubview(title)
        stack.addArrangedSubview(hint)
        hint.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        stack.setCustomSpacing(2, after: title)
        stack.setCustomSpacing(10, after: hint)
        stack.addArrangedSubview(grid)
        grid.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        if grid !== hiddenGrid {
            stack.setCustomSpacing(16, after: grid)
        }
    }

    // MARK: - Layout sync

    /// Pushes `workingLayout` into every grid and the preview.
    private func syncFromWorkingLayout() {
        primaryGrid.setItems(workingLayout.primary)
        sideGrid.setItems(workingLayout.side)
        hiddenGrid.setItems(workingLayout.hidden)
        preview.layout = workingLayout
        updatePreviewHeight()
    }

    /// Pulls the current grid contents back into `workingLayout` and refreshes
    /// the preview. Called after every drag-and-drop edit.
    private func collectWorkingLayout() {
        workingLayout = ToolbarLayout(
            primary: primaryGrid.items,
            side: sideGrid.items,
            hidden: hiddenGrid.items
        ).normalized()
        preview.layout = workingLayout
        updatePreviewHeight()
        Defaults.toolbarLayout = workingLayout
    }

    private func updatePreviewHeight() {
        previewHeightConstraint.constant = preview.preferredHeight
    }

    // MARK: - Actions

    @objc private func resetTapped() {
        workingLayout = .default
        syncFromWorkingLayout()
        Defaults.toolbarLayout = workingLayout
    }

    @objc private func resetShortcutsTapped() {
        cancelShortcutRecording()
        EditorShortcutRegistry.restoreAllDefaults()
        refreshShortcutPresentation()
    }

    @objc private func onLanguageChanged() {
        applyLocalizedStrings()
    }

    @objc private func onShortcutsChanged() {
        refreshShortcutPresentation()
    }

    private func applyLocalizedStrings() {
        primaryTitle.stringValue = L10n.toolbarSettingsPrimaryTitle
        primaryHint.stringValue = L10n.toolbarSettingsPrimaryHint
        sideTitle.stringValue = L10n.toolbarSettingsSideTitle
        sideHint.stringValue = L10n.toolbarSettingsSideHint
        hiddenTitle.stringValue = L10n.toolbarSettingsHiddenTitle
        hiddenHint.stringValue = L10n.toolbarSettingsHiddenHint
        footnote.stringValue = L10n.toolbarSettingsFootnote
        additionalShortcutsTitle.stringValue = L10n.toolbarSettingsAdditionalShortcuts
        shortcutResetButton.title = L10n.toolbarSettingsShortcutResetAll
        resetButton.title = L10n.toolbarSettingsReset
        refreshShortcutPresentation()
    }

    // MARK: - Shortcut editing

    private func beginShortcutRecording(for action: EditorShortcutAction) {
        if recordingAction == action {
            cancelShortcutRecording()
            return
        }
        cancelShortcutRecording()

        recordingAction = action
        HotkeyManager.shared.beginRecording()
        refreshShortcutPresentation()

        shortcutRecordingMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let action = self.recordingAction else { return event }
            let modifiers = HotkeyManager.carbonModifiers(from: event.modifierFlags)
            if event.keyCode == UInt16(kVK_Escape), modifiers == 0 {
                self.cancelShortcutRecording()
                return nil
            }

            let binding = EditorShortcutBinding(event: event)
            if let message = EditorShortcutRegistry.validationMessage(for: binding, assigningTo: action) {
                self.cancelShortcutRecording()
                self.presentShortcutAlert(message)
                return nil
            }

            EditorShortcutRegistry.setBinding(binding, for: action)
            self.finishShortcutRecording()
            return nil
        }
    }

    private func finishShortcutRecording() {
        if let shortcutRecordingMonitor {
            NSEvent.removeMonitor(shortcutRecordingMonitor)
            self.shortcutRecordingMonitor = nil
        }
        recordingAction = nil
        HotkeyManager.shared.endRecording()
        refreshShortcutPresentation()
    }

    func cancelShortcutRecording() {
        guard recordingAction != nil || shortcutRecordingMonitor != nil else { return }
        finishShortcutRecording()
    }

    private func refreshShortcutPresentation() {
        let recordingItem: ToolbarItemID?
        if case .toolbar(let item)? = recordingAction {
            recordingItem = item
        } else {
            recordingItem = nil
        }

        for grid in [primaryGrid, sideGrid, hiddenGrid].compactMap({ $0 }) {
            grid.setShortcutRecordingItem(recordingItem)
            grid.refreshTooltips()
        }
        selectShortcutButton.isRecordingShortcut = recordingAction == .select
        shapeFillShortcutButton.isRecordingShortcut = recordingAction == .shapeFill
        selectShortcutButton.refreshTitle()
        shapeFillShortcutButton.refreshTitle()

        if let recordingAction {
            shortcutHint.stringValue = L10n.toolbarSettingsShortcutRecording(recordingAction.localizedTitle)
        } else {
            shortcutHint.stringValue = L10n.toolbarSettingsShortcutHint
        }
    }

    private func showShortcutContextMenu(
        for action: EditorShortcutAction,
        from view: NSView,
        event: NSEvent
    ) {
        cancelShortcutRecording()
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(ShortcutClosureMenuItem(title: L10n.toolbarSettingsShortcutRecord) { [weak self] in
            self?.beginShortcutRecording(for: action)
        })

        if EditorShortcutRegistry.canDisable(action),
           EditorShortcutRegistry.binding(for: action) != nil {
            menu.addItem(ShortcutClosureMenuItem(title: L10n.toolbarSettingsShortcutClear) {
                EditorShortcutRegistry.disable(action)
            })
        }

        if EditorShortcutRegistry.hasOverride(for: action) {
            menu.addItem(ShortcutClosureMenuItem(title: L10n.toolbarSettingsShortcutRestore) {
                EditorShortcutRegistry.restoreDefault(for: action)
            })
        }

        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    private func presentShortcutAlert(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.shortcutConflictTitle
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    // MARK: - Shared builders

    private static func makeCard() -> NSView {
        let card = NSView()
        card.wantsLayer = true
        card.layer?.cornerRadius = 12
        card.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.04).cgColor
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor.white.withAlphaComponent(0.06).cgColor
        card.translatesAutoresizingMaskIntoConstraints = false
        return card
    }

    private static func sectionTitleLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        label.textColor = NSColor.white.withAlphaComponent(0.92)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    private static func hintLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = NSColor.white.withAlphaComponent(0.45)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    private static func styleButton(_ button: NSButton, title: String, prominent: Bool) {
        button.title = title
        button.bezelStyle = .rounded
        button.controlSize = .large
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setContentHuggingPriority(.required, for: .horizontal)
        if prominent {
            button.bezelColor = NSColor.controlAccentColor
        }
    }
}

private final class EditorShortcutActionButton: NSButton {
    let shortcutAction: EditorShortcutAction
    var onActivate: ((EditorShortcutAction) -> Void)?
    var onContextMenu: ((EditorShortcutAction, NSView, NSEvent) -> Void)?
    var isRecordingShortcut = false {
        didSet { refreshTitle() }
    }

    init(action: EditorShortcutAction) {
        shortcutAction = action
        super.init(frame: .zero)
        bezelStyle = .rounded
        controlSize = .large
        target = self
        self.action = #selector(activate)
        translatesAutoresizingMaskIntoConstraints = false
        refreshTitle()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func refreshTitle() {
        let display = isRecordingShortcut
            ? "…"
            : EditorShortcutRegistry.displayString(for: shortcutAction)
                ?? L10n.toolbarSettingsShortcutNone
        title = "\(shortcutAction.localizedTitle)  \(display)"
        toolTip = title
    }

    override func rightMouseDown(with event: NSEvent) {
        onContextMenu?(shortcutAction, self, event)
    }

    @objc private func activate() {
        onActivate?(shortcutAction)
    }
}

private final class ShortcutClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: nil, keyEquivalent: "")
        target = self
        action = #selector(runHandler)
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func runHandler() {
        handler()
    }
}
