import AppKit

/// On-device recognition only: cloud providers were hidden on 2026-10-26
/// (their code and saved configs stay). Changes apply to the next request.
final class OCRSettingsPane: NSView {
    private let behaviorPopup = NSPopUpButton()
    private let enginePopup = NSPopUpButton()
    private let languagePopup = NSPopUpButton()
    private let engineDescription = NSTextField(wrappingLabelWithString: "")
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private var labels: [String: NSTextField] = [:]
    private var languageRow: NSView?

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        buildUI()
        refreshLocalization()
        NotificationCenter.default.addObserver(self, selector: #selector(languageChanged),
                                               name: .languageDidChange, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { NotificationCenter.default.removeObserver(self) }

    private func buildUI() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -22),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -22)
        ])

        behaviorPopup.target = self
        behaviorPopup.action = #selector(behaviorChanged)
        stack.addArrangedSubview(makeRow("behavior", field: behaviorPopup))

        enginePopup.target = self
        enginePopup.action = #selector(engineChanged)
        let engineRow = makeRow("engine", field: enginePopup)
        stack.addArrangedSubview(engineRow)
        stack.setCustomSpacing(6, after: engineRow)

        for label in [engineDescription, statusLabel] {
            label.font = .systemFont(ofSize: 12)
            label.textColor = .secondaryLabelColor
            label.maximumNumberOfLines = 0
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        stack.addArrangedSubview(engineDescription)

        languagePopup.target = self
        languagePopup.action = #selector(languageSetChanged)
        let languageRow = makeRow("languageSet", field: languagePopup)
        self.languageRow = languageRow
        stack.addArrangedSubview(languageRow)

        stack.addArrangedSubview(statusLabel)
        for view in stack.arrangedSubviews {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }

    private func makeRow(_ key: String, field: NSView) -> NSView {
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 12, weight: .medium)
        labels[key] = label
        let row = NSStackView(views: [label, field])
        row.orientation = .vertical
        row.alignment = .leading
        row.spacing = 6
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalTo: row.widthAnchor).isActive = true
        return row
    }

    @objc private func languageChanged() { refreshLocalization() }

    @objc private func behaviorChanged() {
        let cases = Defaults.OCRResultBehavior.allCases
        guard cases.indices.contains(behaviorPopup.indexOfSelectedItem) else { return }
        Defaults.ocrResultBehavior = cases[behaviorPopup.indexOfSelectedItem]
    }

    @objc private func engineChanged() {
        let cases = Defaults.OCREngine.allCases
        guard cases.indices.contains(enginePopup.indexOfSelectedItem) else { return }
        Defaults.ocrEngine = cases[enginePopup.indexOfSelectedItem]
        refreshLocalization()
    }

    @objc private func languageSetChanged() {
        let cases = Defaults.OCRLanguageSet.allCases
        guard cases.indices.contains(languagePopup.indexOfSelectedItem) else { return }
        Defaults.ocrLanguageSet = cases[languagePopup.indexOfSelectedItem]
        OCRService.warmUp()
    }

    private func refreshLocalization() {
        behaviorPopup.removeAllItems()
        behaviorPopup.addItems(withTitles: [L10n.ocrResultBehaviorCopy, L10n.ocrResultBehaviorPanel])
        behaviorPopup.selectItem(at: Defaults.OCRResultBehavior.allCases.firstIndex(of: Defaults.ocrResultBehavior) ?? 0)
        labels["behavior"]?.stringValue = L10n.ocrResultBehaviorLabel

        enginePopup.removeAllItems()
        enginePopup.addItems(withTitles: [L10n.ocrEngineAuto, L10n.ocrEngineSystem, L10n.ocrEngineBundled])
        enginePopup.selectItem(at: Defaults.OCREngine.allCases.firstIndex(of: Defaults.ocrEngine) ?? 0)
        labels["engine"]?.stringValue = L10n.ocrEngineLabel
        engineDescription.stringValue = L10n.ocrEngineDescription

        languagePopup.removeAllItems()
        languagePopup.addItems(withTitles: [L10n.ocrLanguageSetChineseEnglish, L10n.ocrLanguageSetEastAsian])
        languagePopup.selectItem(at: Defaults.OCRLanguageSet.allCases.firstIndex(of: Defaults.ocrLanguageSet) ?? 0)
        labels["languageSet"]?.stringValue = L10n.ocrLanguageSetLabel
        // The languages only steer Vision; the built-in model has its own set.
        languageRow?.isHidden = Defaults.ocrEngine == .bundled

        statusLabel.stringValue = L10n.ocrSettingsSaved
    }
}
