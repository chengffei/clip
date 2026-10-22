import AppKit

final class FilenameRuleCard: NSView, NSTextFieldDelegate {
    private enum Preset: Int, CaseIterable {
        case custom
        case short
        case compact
        case unique
        case counter
        case restore

        var title: String {
            switch self {
            case .custom: return L10n.filenameRulePresetCustom
            case .short: return L10n.filenameRulePresetShort
            case .compact: return L10n.filenameRulePresetCompact
            case .unique: return L10n.filenameRulePresetUnique
            case .counter: return L10n.filenameRulePresetCounter
            case .restore: return L10n.filenameRulePresetRestore
            }
        }

        var imageTemplate: String {
            switch self {
            case .custom: return Defaults.imageFilenameTemplate
            case .short: return "capcap-{date}-{time}"
            case .compact: return "c-{date}-{time}"
            case .unique: return "capcap-{date}-{time}-{rand:3}"
            case .counter: return "capcap-{date}-{daily:3}"
            case .restore: return Defaults.defaultImageFilenameTemplate
            }
        }

        var recordingTemplate: String {
            switch self {
            case .custom: return Defaults.recordingFilenameTemplate
            case .short: return "capcap-rec-{date}-{time}"
            case .compact: return "r-{date}-{time}"
            case .unique: return "capcap-rec-{date}-{time}-{rand:3}"
            case .counter: return "capcap-rec-{date}-{daily:3}"
            case .restore: return Defaults.defaultRecordingFilenameTemplate
            }
        }
    }

    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(wrappingLabelWithString: "")
    private let presetLabel = NSTextField(labelWithString: "")
    private let presetPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let imageLabel = NSTextField(labelWithString: "")
    private let recordingLabel = NSTextField(labelWithString: "")
    private let variablesLabel = NSTextField(labelWithString: "")
    private let imageField = PasteableTextField()
    private let recordingField = PasteableTextField()
    private let imagePreviewLabel = NSTextField(labelWithString: "")
    private let recordingPreviewLabel = NSTextField(labelWithString: "")
    private var variableButtons: [(button: NSButton, token: String)] = []
    private weak var activeField: NSTextField?
    private var imageCursorLocation = 0
    private var recordingCursorLocation = 0

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.04).cgColor
        layer?.borderColor = NSColor.white.withAlphaComponent(0.06).cgColor
        layer?.borderWidth = 1

        imageField.stringValue = Defaults.imageFilenameTemplate
        recordingField.stringValue = Defaults.recordingFilenameTemplate
        imageField.delegate = self
        recordingField.delegate = self
        imageField.onFocus = { [weak self] field in self?.activateField(field) }
        recordingField.onFocus = { [weak self] field in self?.activateField(field) }
        imageCursorLocation = (imageField.stringValue as NSString).length
        recordingCursorLocation = (recordingField.stringValue as NSString).length
        activeField = imageField

        buildUI()
        refreshLocalization()
        updatePreviews()
        syncPresetSelection()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func refreshLocalization() {
        titleLabel.stringValue = L10n.filenameRuleTitle
        subtitleLabel.stringValue = L10n.filenameRuleSubtitle
        titleLabel.toolTip = L10n.filenameRuleSubtitle
        presetLabel.stringValue = L10n.filenameRulePresetLabel
        imageLabel.stringValue = L10n.filenameRuleImageLabel
        recordingLabel.stringValue = L10n.filenameRuleRecordingLabel
        variablesLabel.stringValue = L10n.filenameRuleVariablesLabel

        let selected = presetPopup.indexOfSelectedItem
        presetPopup.removeAllItems()
        Preset.allCases.forEach { presetPopup.addItem(withTitle: $0.title) }
        if selected >= 0, selected < presetPopup.numberOfItems {
            presetPopup.selectItem(at: selected)
        }

        let labels = [
            L10n.filenameRuleVariableDate,
            L10n.filenameRuleVariableTime,
            L10n.filenameRuleVariableDaily,
            L10n.filenameRuleVariableRandom,
            L10n.filenameRuleVariableSize,
        ]
        for (index, label) in labels.enumerated() where index < variableButtons.count {
            variableButtons[index].button.title = label
        }
        updatePreviews()
        syncPresetSelection()
    }

    private func buildUI() {
        let inner = NSStackView()
        inner.orientation = .vertical
        inner.alignment = .leading
        inner.spacing = 10
        inner.translatesAutoresizingMaskIntoConstraints = false
        addSubview(inner)

        configurePrimaryLabel(titleLabel)
        configureSecondaryLabel(subtitleLabel, monospaced: false)
        subtitleLabel.maximumNumberOfLines = 0
        subtitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let header = NSStackView(views: [titleLabel])
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 3
        header.translatesAutoresizingMaskIntoConstraints = false
        inner.addArrangedSubview(header)
        header.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true

        let headerDivider = rowDivider()
        inner.addArrangedSubview(headerDivider)
        headerDivider.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true

        presetPopup.controlSize = .small
        presetPopup.font = NSFont.systemFont(ofSize: 12)
        presetPopup.target = self
        presetPopup.action = #selector(presetChanged)
        presetPopup.translatesAutoresizingMaskIntoConstraints = false
        presetPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
        let presetRow = makeSingleLineRow(label: presetLabel, control: presetPopup)
        inner.addArrangedSubview(presetRow)
        presetRow.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true

        let imageDivider = rowDivider()
        inner.addArrangedSubview(imageDivider)
        imageDivider.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true

        let imageSection = makeTemplateSection(label: imageLabel, field: imageField, preview: imagePreviewLabel)
        inner.addArrangedSubview(imageSection)
        imageSection.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true

        let recordingDivider = rowDivider()
        inner.addArrangedSubview(recordingDivider)
        recordingDivider.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true

        let recordingSection = makeTemplateSection(label: recordingLabel, field: recordingField, preview: recordingPreviewLabel)
        inner.addArrangedSubview(recordingSection)
        recordingSection.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true

        let variablesDivider = rowDivider()
        inner.addArrangedSubview(variablesDivider)
        variablesDivider.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true

        let variablesSection = makeVariablesSection()
        inner.addArrangedSubview(variablesSection)
        variablesSection.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true

        NSLayoutConstraint.activate([
            inner.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            inner.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            inner.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            inner.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
        ])
    }

    private func configurePrimaryLabel(_ label: NSTextField) {
        label.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        label.textColor = NSColor.white.withAlphaComponent(0.94)
        label.alignment = .left
    }

    private func configureSecondaryLabel(_ label: NSTextField, monospaced: Bool = true) {
        label.font = monospaced
            ? NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            : NSFont.systemFont(ofSize: 11)
        label.textColor = NSColor.white.withAlphaComponent(0.58)
        label.alignment = .left
    }

    private func rowDivider() -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
        v.translatesAutoresizingMaskIntoConstraints = false
        v.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return v
    }

    private func makeSingleLineRow(label: NSTextField, control: NSView) -> NSView {
        configurePrimaryLabel(label)
        label.translatesAutoresizingMaskIntoConstraints = false

        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(label)
        row.addSubview(control)

        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            label.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: control.leadingAnchor, constant: -12),

            control.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            control.topAnchor.constraint(equalTo: row.topAnchor),
            control.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            control.widthAnchor.constraint(greaterThanOrEqualToConstant: 240),
        ])

        return row
    }

    private func makeTemplateSection(label: NSTextField, field: NSTextField, preview: NSTextField) -> NSView {
        configurePrimaryLabel(label)
        label.translatesAutoresizingMaskIntoConstraints = false

        field.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        field.translatesAutoresizingMaskIntoConstraints = false
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        configureSecondaryLabel(preview)
        preview.lineBreakMode = .byTruncatingMiddle
        preview.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let valueStack = NSStackView(views: [field, preview])
        valueStack.orientation = .vertical
        valueStack.alignment = .leading
        valueStack.spacing = 4
        valueStack.translatesAutoresizingMaskIntoConstraints = false

        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(label)
        row.addSubview(valueStack)

        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        valueStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        valueStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            label.firstBaselineAnchor.constraint(equalTo: field.firstBaselineAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: valueStack.leadingAnchor, constant: -12),

            valueStack.topAnchor.constraint(equalTo: row.topAnchor),
            valueStack.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            valueStack.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            field.widthAnchor.constraint(equalTo: valueStack.widthAnchor),
            preview.widthAnchor.constraint(equalTo: valueStack.widthAnchor),
            valueStack.widthAnchor.constraint(greaterThanOrEqualToConstant: 360),
        ])

        return row
    }

    private func makeVariablesSection() -> NSView {
        configurePrimaryLabel(variablesLabel)
        variablesLabel.translatesAutoresizingMaskIntoConstraints = false

        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 8
        buttonRow.translatesAutoresizingMaskIntoConstraints = false

        let tokens = ["{date}", "{time}", "{daily:3}", "{rand:4}", "{width}x{height}"]
        for token in tokens {
            let button = NSButton(title: "", target: self, action: #selector(insertVariable(_:)))
            button.bezelStyle = .rounded
            button.controlSize = .small
            button.font = NSFont.systemFont(ofSize: 11)
            button.identifier = NSUserInterfaceItemIdentifier(token)
            button.refusesFirstResponder = true
            variableButtons.append((button, token))
            buttonRow.addArrangedSubview(button)
        }

        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(variablesLabel)
        row.addSubview(buttonRow)

        variablesLabel.setContentHuggingPriority(.required, for: .horizontal)
        variablesLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        buttonRow.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        NSLayoutConstraint.activate([
            variablesLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            variablesLabel.centerYAnchor.constraint(equalTo: buttonRow.centerYAnchor),
            variablesLabel.trailingAnchor.constraint(lessThanOrEqualTo: buttonRow.leadingAnchor, constant: -12),

            buttonRow.topAnchor.constraint(equalTo: row.topAnchor),
            buttonRow.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            buttonRow.bottomAnchor.constraint(equalTo: row.bottomAnchor),
        ])

        return row
    }

    @objc private func presetChanged(_ sender: NSPopUpButton) {
        guard let preset = Preset(rawValue: sender.indexOfSelectedItem), preset != .custom else {
            return
        }
        imageField.stringValue = preset.imageTemplate
        recordingField.stringValue = preset.recordingTemplate
        imageCursorLocation = (imageField.stringValue as NSString).length
        recordingCursorLocation = (recordingField.stringValue as NSString).length
        persistTemplates()
        updatePreviews()
        syncPresetSelection()
    }

    @objc private func insertVariable(_ sender: NSButton) {
        let token = sender.identifier?.rawValue ?? ""
        guard !token.isEmpty else { return }
        let field = currentlyEditingField() ?? activeField ?? imageField
        activateField(field)
        updateStoredCursor(for: field)

        let insertionLocation: Int
        let newLocation: Int
        if let editor = field.currentEditor() {
            let textLength = (editor.string as NSString).length
            insertionLocation = min(max(storedCursorLocation(for: field), 0), textLength)
            editor.replaceCharacters(in: NSRange(location: insertionLocation, length: 0), with: token)
            newLocation = insertionLocation + (token as NSString).length
            editor.selectedRange = NSRange(location: newLocation, length: 0)
            field.stringValue = editor.string
        } else {
            let mutable = NSMutableString(string: field.stringValue)
            insertionLocation = min(max(storedCursorLocation(for: field), 0), mutable.length)
            mutable.insert(token, at: insertionLocation)
            newLocation = insertionLocation + (token as NSString).length
            field.stringValue = mutable as String
        }

        setStoredCursorLocation(newLocation, for: field)
        persistTemplates()
        updatePreviews()
        syncPresetSelection()

        window?.makeFirstResponder(field)
        field.currentEditor()?.selectedRange = NSRange(location: newLocation, length: 0)
    }

    func controlTextDidBeginEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        activateField(field)
        updateStoredCursor(for: field)
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        updateStoredCursor(for: field)
        persistTemplates()
        updatePreviews()
        syncPresetSelection()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        activateField(field)
        updateStoredCursor(for: field)
    }

    private func activateField(_ field: NSTextField) {
        guard field === imageField || field === recordingField else { return }
        activeField = field
    }

    private func currentlyEditingField() -> NSTextField? {
        guard let firstResponder = window?.firstResponder as? NSText else { return nil }
        if imageField.currentEditor() === firstResponder { return imageField }
        if recordingField.currentEditor() === firstResponder { return recordingField }
        return nil
    }

    private func updateStoredCursor(for field: NSTextField) {
        guard let editor = field.currentEditor() else { return }
        setStoredCursorLocation(editor.selectedRange.location, for: field)
    }

    private func storedCursorLocation(for field: NSTextField) -> Int {
        field === recordingField ? recordingCursorLocation : imageCursorLocation
    }

    private func setStoredCursorLocation(_ location: Int, for field: NSTextField) {
        let length = (field.stringValue as NSString).length
        let clamped = min(max(location, 0), length)
        if field === recordingField {
            recordingCursorLocation = clamped
        } else {
            imageCursorLocation = clamped
        }
    }

    private func persistTemplates() {
        Defaults.imageFilenameTemplate = imageField.stringValue
        Defaults.recordingFilenameTemplate = recordingField.stringValue
    }

    private func updatePreviews() {
        imagePreviewLabel.stringValue = L10n.filenameRulePreview(
            FilenameTemplate.previewFileName(
                kind: .image,
                template: imageField.stringValue,
                fileExtension: "png"
            )
        )
        recordingPreviewLabel.stringValue = L10n.filenameRulePreview(
            FilenameTemplate.previewFileName(
                kind: .recording,
                template: recordingField.stringValue,
                fileExtension: "mp4",
                imageSize: nil
            )
        )
    }

    private func syncPresetSelection() {
        let imageTemplate = imageField.stringValue
        let recordingTemplate = recordingField.stringValue
        let matchingPreset = Preset.allCases.first { preset in
            guard preset != .custom, preset != .restore else { return false }
            return preset.imageTemplate == imageTemplate && preset.recordingTemplate == recordingTemplate
        }
        presetPopup.selectItem(at: (matchingPreset ?? .custom).rawValue)
    }
}
