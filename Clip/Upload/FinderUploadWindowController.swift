import AppKit
import ImageIO
import UniformTypeIdentifiers

private final class FinderUploadWindow: NSPanel {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if modifiers == .command,
           event.charactersIgnoringModifiers?.lowercased() == "w" {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

private final class FinderUploadItem {
    enum State {
        case pending
        case uploading(Double)
        case succeeded(URL)
        case failed(String)
    }

    let url: URL
    let displayName: String
    let detail: String
    let thumbnail: NSImage
    var isSelected = true
    var state: State = .pending

    init(url: URL) {
        self.url = url
        self.displayName = url.lastPathComponent

        let values = try? url.resourceValues(forKeys: [.contentTypeKey, .fileSizeKey])
        let typeName = values?.contentType?.preferredFilenameExtension?.uppercased()
            ?? url.pathExtension.uppercased()
        let sizeText: String
        if let size = values?.fileSize {
            sizeText = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
        } else {
            sizeText = L10n.finderUploadUnknownSize
        }
        self.detail = typeName.isEmpty ? sizeText : "\(typeName) · \(sizeText)"
        self.thumbnail = Self.makeThumbnail(for: url)
    }

    private static func makeThumbnail(for url: URL) -> NSImage {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 96,
        ]
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
            return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        }

        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 40, height: 40)
        return icon
    }
}

private final class FinderUploadFileRowView: NSTableCellView {
    private let checkbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let thumbnailView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private var onSelectionChange: ((Bool) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        checkbox.target = self
        checkbox.action = #selector(selectionChanged)
        checkbox.allowsMixedState = false
        checkbox.translatesAutoresizingMaskIntoConstraints = false
        addSubview(checkbox)

        thumbnailView.imageScaling = .scaleProportionallyUpOrDown
        thumbnailView.imageAlignment = .alignCenter
        thumbnailView.wantsLayer = true
        thumbnailView.layer?.cornerRadius = 7
        thumbnailView.layer?.cornerCurve = .continuous
        thumbnailView.layer?.masksToBounds = true
        thumbnailView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        thumbnailView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(thumbnailView)

        nameLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        nameLabel.textColor = .labelColor
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(nameLabel)

        detailLabel.font = NSFont.systemFont(ofSize: 11)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(detailLabel)

        statusLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        statusLabel.alignment = .right
        statusLabel.setContentHuggingPriority(.required, for: .horizontal)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(statusLabel)

        NSLayoutConstraint.activate([
            checkbox.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            checkbox.centerYAnchor.constraint(equalTo: centerYAnchor),

            thumbnailView.leadingAnchor.constraint(equalTo: checkbox.trailingAnchor, constant: 10),
            thumbnailView.centerYAnchor.constraint(equalTo: centerYAnchor),
            thumbnailView.widthAnchor.constraint(equalToConstant: 40),
            thumbnailView.heightAnchor.constraint(equalToConstant: 40),

            nameLabel.leadingAnchor.constraint(equalTo: thumbnailView.trailingAnchor, constant: 12),
            nameLabel.topAnchor.constraint(equalTo: topAnchor, constant: 11),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: statusLabel.leadingAnchor, constant: -12),

            detailLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            detailLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 3),
            detailLabel.trailingAnchor.constraint(lessThanOrEqualTo: statusLabel.leadingAnchor, constant: -12),

            statusLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            statusLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            statusLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 54),
        ])
    }

    func configure(
        item: FinderUploadItem,
        selectionEnabled: Bool,
        onSelectionChange: @escaping (Bool) -> Void
    ) {
        self.onSelectionChange = onSelectionChange
        checkbox.state = item.isSelected ? .on : .off
        checkbox.isEnabled = selectionEnabled && !item.isSucceeded
        thumbnailView.image = item.thumbnail
        thumbnailView.alphaValue = item.isSelected || item.isSucceeded ? 1 : 0.45
        nameLabel.stringValue = item.displayName
        nameLabel.textColor = item.isSelected || item.isSucceeded ? .labelColor : .tertiaryLabelColor

        switch item.state {
        case .pending:
            detailLabel.stringValue = item.detail
            detailLabel.textColor = .secondaryLabelColor
            statusLabel.stringValue = ""
            statusLabel.textColor = .secondaryLabelColor
        case .uploading(let progress):
            detailLabel.stringValue = item.detail
            detailLabel.textColor = .secondaryLabelColor
            statusLabel.stringValue = "\(Int((progress * 100).rounded()))%"
            statusLabel.textColor = .controlAccentColor
        case .succeeded:
            detailLabel.stringValue = item.detail
            detailLabel.textColor = .secondaryLabelColor
            statusLabel.stringValue = L10n.finderUploadSucceeded
            statusLabel.textColor = .systemGreen
        case .failed:
            detailLabel.stringValue = item.detail
            detailLabel.textColor = .secondaryLabelColor
            statusLabel.stringValue = L10n.finderUploadFailed
            statusLabel.textColor = .systemRed
        }

        setAccessibilityLabel(item.displayName)
        setAccessibilityValue(statusLabel.stringValue)
    }

    @objc private func selectionChanged() {
        onSelectionChange?(checkbox.state == .on)
    }
}

private extension FinderUploadItem {
    var isSucceeded: Bool {
        if case .succeeded = state { return true }
        return false
    }

    var uploadedURL: URL? {
        if case .succeeded(let url) = state { return url }
        return nil
    }
}

/// Confirmation and progress dialog for uploading regular files.
/// Files are uploaded sequentially so a large selection does not create a
/// burst of in-memory request bodies.
final class FinderUploadWindowController: NSWindowController,
    NSWindowDelegate,
    NSTableViewDataSource,
    NSTableViewDelegate {

    private let items: [FinderUploadItem]
    private let onClose: () -> Void
    private let tableView = NSTableView()
    private let summaryLabel = NSTextField(labelWithString: "")
    private let selectAllButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let uploadButton = NSButton(title: "", target: nil, action: nil)
    private let uploadSpinner = NSProgressIndicator()
    private let errorContainer = AdaptiveChromeSurfaceView(style: .card, cornerRadius: 9, borderWidth: 1)
    private let errorTitleLabel = NSTextField(labelWithString: "")
    private let errorTextView = NSTextView()
    private var isUploading = false
    private var hasAttemptedUpload = false
    private var activeFailures: [String] = []

    init(fileURLs: [URL], onClose: @escaping () -> Void) {
        self.items = fileURLs.map(FinderUploadItem.init)
        self.onClose = onClose

        let window = FinderUploadWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.finderUploadDialogTitle
        window.isReleasedWhenClosed = false
        window.backgroundColor = AdaptiveChrome.panelBackground
        window.appearance = NSAppearance(named: .darkAqua)
        window.center()

        super.init(window: window)
        window.delegate = self
        window.contentView = buildContentView()
        configureTable()
        refreshControls()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        !isUploading
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        items.count
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        false
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("FinderUploadFileRow")
        let rowView = tableView.makeView(withIdentifier: identifier, owner: self) as? FinderUploadFileRowView
            ?? FinderUploadFileRowView(frame: .zero)
        rowView.identifier = identifier
        let item = items[row]
        rowView.configure(item: item, selectionEnabled: !isUploading) { [weak self, weak item] selected in
            guard let self, let item else { return }
            item.isSelected = selected
            self.refreshControls()
            self.reload(item)
        }
        return rowView
    }

    private func buildContentView() -> NSView {
        let root = AdaptiveChromeSurfaceView(style: .panel)

        let header = NSStackView()
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 4

        let titleLabel = NSTextField(labelWithString: L10n.finderUploadDialogHeading)
        titleLabel.font = NSFont.systemFont(ofSize: 20, weight: .semibold)
        titleLabel.textColor = .labelColor
        header.addArrangedSubview(titleLabel)

        summaryLabel.font = NSFont.systemFont(ofSize: 12)
        summaryLabel.textColor = .secondaryLabelColor
        header.addArrangedSubview(summaryLabel)

        let listCard = AdaptiveChromeSurfaceView(style: .card, cornerRadius: 10, borderWidth: 1)
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = tableView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        listCard.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: listCard.leadingAnchor, constant: 1),
            scrollView.trailingAnchor.constraint(equalTo: listCard.trailingAnchor, constant: -1),
            scrollView.topAnchor.constraint(equalTo: listCard.topAnchor, constant: 1),
            scrollView.bottomAnchor.constraint(equalTo: listCard.bottomAnchor, constant: -1),
            listCard.heightAnchor.constraint(greaterThanOrEqualToConstant: 250),
        ])

        buildErrorContainer()
        errorContainer.isHidden = true
        errorContainer.heightAnchor.constraint(equalToConstant: 104).isActive = true

        let separator = AdaptiveSeparatorView(frame: .zero)
        separator.heightAnchor.constraint(equalToConstant: 1).isActive = true

        let footer = NSStackView()
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 12

        selectAllButton.title = L10n.finderUploadSelectAll
        selectAllButton.target = self
        selectAllButton.action = #selector(selectAllChanged)
        selectAllButton.allowsMixedState = true
        footer.addArrangedSubview(selectAllButton)
        footer.addArrangedSubview(NSView())

        uploadButton.target = self
        uploadButton.action = #selector(uploadClicked)
        uploadButton.bezelStyle = .rounded
        uploadButton.bezelColor = .controlAccentColor
        uploadButton.controlSize = .large
        uploadButton.keyEquivalent = "\r"
        uploadButton.translatesAutoresizingMaskIntoConstraints = false
        uploadButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 176).isActive = true
        uploadButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 32).isActive = true
        footer.addArrangedSubview(uploadButton)

        uploadSpinner.style = .spinning
        uploadSpinner.controlSize = .small
        uploadSpinner.isDisplayedWhenStopped = false
        uploadSpinner.translatesAutoresizingMaskIntoConstraints = false
        uploadButton.addSubview(uploadSpinner)
        NSLayoutConstraint.activate([
            uploadSpinner.leadingAnchor.constraint(equalTo: uploadButton.leadingAnchor, constant: 12),
            uploadSpinner.centerYAnchor.constraint(equalTo: uploadButton.centerYAnchor),
        ])

        let stack = NSStackView(views: [header, listCard, errorContainer, separator, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -18),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
            listCard.widthAnchor.constraint(equalTo: stack.widthAnchor),
            errorContainer.widthAnchor.constraint(equalTo: stack.widthAnchor),
            separator.widthAnchor.constraint(equalTo: stack.widthAnchor),
            footer.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        return root
    }

    private func buildErrorContainer() {
        errorTitleLabel.stringValue = L10n.finderUploadErrorLogTitle
        errorTitleLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        errorTitleLabel.textColor = .systemRed
        errorTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        errorContainer.addSubview(errorTitleLabel)

        errorTextView.isEditable = false
        errorTextView.isSelectable = true
        errorTextView.drawsBackground = false
        errorTextView.font = NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular)
        errorTextView.textColor = NSColor.systemRed.blended(withFraction: 0.25, of: .labelColor)
        errorTextView.textContainerInset = NSSize(width: 0, height: 2)

        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = errorTextView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        errorContainer.addSubview(scrollView)

        NSLayoutConstraint.activate([
            errorTitleLabel.leadingAnchor.constraint(equalTo: errorContainer.leadingAnchor, constant: 12),
            errorTitleLabel.trailingAnchor.constraint(equalTo: errorContainer.trailingAnchor, constant: -12),
            errorTitleLabel.topAnchor.constraint(equalTo: errorContainer.topAnchor, constant: 9),
            scrollView.leadingAnchor.constraint(equalTo: errorContainer.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: errorContainer.trailingAnchor, constant: -12),
            scrollView.topAnchor.constraint(equalTo: errorTitleLabel.bottomAnchor, constant: 4),
            scrollView.bottomAnchor.constraint(equalTo: errorContainer.bottomAnchor, constant: -8),
        ])
    }

    private func configureTable() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("FinderUploadFile"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 62
        tableView.intercellSpacing = NSSize(width: 0, height: 1)
        tableView.backgroundColor = .clear
        tableView.gridStyleMask = []
        tableView.selectionHighlightStyle = .none
        tableView.dataSource = self
        tableView.delegate = self
    }

    @objc private func selectAllChanged() {
        guard !isUploading else { return }
        let selectableItems = items.filter { !$0.isSucceeded }
        // AppKit can advance an allowsMixedState checkbox through `.mixed`
        // after `.off`. Derive the next action from the file model instead of
        // trusting that transient control state so an empty selection always
        // becomes fully selected on the next click.
        let shouldSelect = selectableItems.contains { !$0.isSelected }
        for item in selectableItems {
            item.isSelected = shouldSelect
        }
        tableView.reloadData()
        refreshControls()
    }

    @objc private func uploadClicked() {
        guard !isUploading else { return }
        let selectedItems = items.filter { $0.isSelected && !$0.isSucceeded }
        guard !selectedItems.isEmpty else { return }

        guard let kind = Defaults.defaultUploadProviderKind,
              let config = ProviderConfigStore.load(kind: kind) else {
            showErrorLog([L10n.uploadNoProvider])
            return
        }
        let provider = Uploaders.provider(for: kind)
        if let message = provider.validate(config) {
            showErrorLog([message])
            return
        }

        hasAttemptedUpload = true
        activeFailures.removeAll()
        errorContainer.isHidden = true
        isUploading = true
        selectAllButton.isEnabled = false
        uploadButton.isEnabled = false
        uploadSpinner.startAnimation(nil)
        tableView.reloadData()
        upload(items: selectedItems, index: 0, provider: provider, config: config)
    }

    private func upload(
        items uploadItems: [FinderUploadItem],
        index: Int,
        provider: UploaderProtocol.Type,
        config: ProviderConfig
    ) {
        guard index < uploadItems.count else {
            finishUploadBatch()
            return
        }

        let item = uploadItems[index]
        item.state = .uploading(0)
        reload(item)
        uploadButton.title = L10n.finderUploadingProgress(index + 1, uploadItems.count)

        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak item] in
            guard let self, let item else { return }
            let result: Result<(Data, String, UTType?), Error>
            do {
                let values = try item.url.resourceValues(forKeys: [.contentTypeKey, .isRegularFileKey])
                guard values.isRegularFile == true else {
                    throw CocoaError(.fileReadUnsupportedScheme)
                }
                let data = try Data(contentsOf: item.url, options: .mappedIfSafe)
                result = .success((data, values.contentType?.preferredMIMEType ?? "application/octet-stream", values.contentType))
            } catch {
                result = .failure(error)
            }

            DispatchQueue.main.async { [weak self, weak item] in
                guard let self, let item else { return }
                switch result {
                case .failure(let error):
                    let message = L10n.finderUploadReadFailed(error.localizedDescription)
                    item.state = .failed(message)
                    self.activeFailures.append("\(item.displayName) — \(message)")
                    self.reload(item)
                    self.upload(items: uploadItems, index: index + 1, provider: provider, config: config)

                case .success(let (data, contentType, uniformType)):
                    provider.upload(
                        data: data,
                        fileName: item.displayName,
                        contentType: contentType,
                        config: config,
                        progress: { [weak self, weak item] progress in
                            guard let self, let item else { return }
                            item.state = .uploading(min(max(progress, 0), 1))
                            self.reload(item)
                        },
                        completion: { [weak self, weak item] result in
                            guard let self, let item else { return }
                            switch result {
                            case .success(let url):
                                item.state = .succeeded(url)
                                item.isSelected = false
                                if uniformType?.conforms(to: .image) == true,
                                   let image = NSImage(data: data) {
                                    HistoryManager.shared.add(image: image, cloudURL: url)
                                }
                            case .failure(let error):
                                let message = (error as? UploadError)?.errorDescription
                                    ?? error.localizedDescription
                                item.state = .failed(message)
                                item.isSelected = true
                                self.activeFailures.append("\(item.displayName) — \(message)")
                            }
                            self.reload(item)
                            self.upload(items: uploadItems, index: index + 1, provider: provider, config: config)
                        }
                    )
                }
            }
        }
    }

    private func finishUploadBatch() {
        isUploading = false
        uploadSpinner.stopAnimation(nil)
        selectAllButton.isEnabled = true
        tableView.reloadData()

        if activeFailures.isEmpty {
            copyUploadedLinks()
            let uploadedCount = items.compactMap(\.uploadedURL).count
            let screen = window?.screen
            close()
            ToastWindow.show(
                message: L10n.finderUploadCompleted(uploadedCount),
                on: screen,
                duration: 2.5
            )
            return
        }

        showErrorLog(activeFailures)
        refreshControls()
    }

    private func copyUploadedLinks() {
        let urls = items.compactMap(\.uploadedURL)
        guard !urls.isEmpty else { return }
        let asMarkdown = Defaults.copyUploadAsMarkdown
        let text = urls.map { url in
            asMarkdown ? "![](\(url.absoluteString))" : url.absoluteString
        }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func showErrorLog(_ lines: [String]) {
        errorTextView.string = lines.joined(separator: "\n")
        errorContainer.isHidden = false
        refreshControls()
    }

    private func refreshControls() {
        let selectableItems = items.filter { !$0.isSucceeded }
        let selectedCount = selectableItems.filter(\.isSelected).count
        let providerName = Defaults.defaultUploadProviderKind?.displayName ?? L10n.uploadDefaultNone
        summaryLabel.stringValue = L10n.finderUploadSummary(selectedCount, providerName)

        if selectableItems.isEmpty || selectedCount == selectableItems.count {
            selectAllButton.state = .on
        } else if selectedCount == 0 {
            selectAllButton.state = .off
        } else {
            selectAllButton.state = .mixed
        }

        guard !isUploading else { return }
        uploadButton.title = hasAttemptedUpload
            ? L10n.finderUploadRetryAction(selectedCount)
            : L10n.finderUploadAction(selectedCount)
        uploadButton.isEnabled = selectedCount > 0
    }

    private func reload(_ item: FinderUploadItem) {
        guard let row = items.firstIndex(where: { $0 === item }) else { return }
        tableView.reloadData(
            forRowIndexes: IndexSet(integer: row),
            columnIndexes: IndexSet(integer: 0)
        )
    }
}
