import AppKit
import Carbon
import Darwin
import QuickLookUI

/// Owns one on-demand Quick Look renderer. History thumbnails never instantiate
/// this controller. Switching clears the previous item while reusing the system
/// renderer; closing the window releases that renderer explicitly.
final class HistoryFileQuickLookWindowController: NSWindowController, NSWindowDelegate {
    private static var current: HistoryFileQuickLookWindowController?
    static var isPresented: Bool { current?.window?.isVisible == true }

    private let references: [HistoryFileReferences.Reference]
    private var currentIndex: Int
    private let filenameLabel = NSTextField(labelWithString: "")
    private let filenameContainer = NSView(frame: NSRect(x: 0, y: 0, width: 0, height: 24))
    private let positionLabel = NSTextField(labelWithString: "")
    private let titlebarHeader = NSStackView()
    private let previousButton = NSButton()
    private let nextButton = NSButton()
    private let retryButton = NSButton()
    private let previewHost = NSView()
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private var previewView: QLPreviewView?
    private var sourceWatcher: DispatchSourceFileSystemObject?
    private var reloadWorkItem: DispatchWorkItem?
    private var pendingSourceEvents: DispatchSource.FileSystemEvent = []
    private var sourceRequest: HistoryImagePreviewRequest?
    private var loadGeneration = 0
    private var hasStartedLoading = false
    private var isClosed = false
    var onClose: (() -> Void)?

    init(references: [HistoryFileReferences.Reference], initialIndex: Int = 0) {
        precondition(!references.isEmpty)
        self.references = references
        currentIndex = min(max(0, initialIndex), references.count - 1)
        let panel = HistoryFileQuickLookPanel(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false
        )
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = AdaptiveChrome.panelBackground
        panel.contentMinSize = NSSize(width: 420, height: 300)
        super.init(window: panel)
        panel.delegate = self
        panel.onKeyDown = { [weak self] event in self?.handleKey(event) ?? false }
        setupContent()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        sourceRequest?.cancel()
        reloadWorkItem?.cancel()
        sourceWatcher?.cancel()
        previewView?.close()
    }

    func show(relativeTo screen: NSScreen?) {
        Self.current?.close()
        Self.current = self
        if let screen = screen ?? NSScreen.main, let window {
            let visible = screen.visibleFrame.insetBy(dx: 20, dy: 20)
            let size = NSSize(width: min(760, visible.width), height: min(600, visible.height))
            window.setFrame(NSRect(x: visible.midX - size.width / 2,
                                   y: visible.midY - size.height / 2,
                                   width: size.width, height: size.height), display: false)
        }
        updateTitlebarLayout()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        loadCurrentItem()
    }

    private func setupContent() {
        guard let content = window?.contentView else { return }
        let header = titlebarHeader
        header.orientation = .horizontal
        header.spacing = 6
        header.alignment = .centerY
        header.detachesHiddenViews = true
        header.edgeInsets = NSEdgeInsets(top: 0, left: 2, bottom: 0, right: 8)

        filenameLabel.lineBreakMode = .byTruncatingTail
        filenameLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        filenameLabel.textColor = .labelColor
        filenameLabel.maximumNumberOfLines = 1
        filenameLabel.frame = filenameContainer.bounds
        filenameLabel.autoresizingMask = [.width, .height]
        filenameContainer.addSubview(filenameLabel)
        let filenameAccessory = NSTitlebarAccessoryViewController()
        filenameAccessory.layoutAttribute = .left
        filenameAccessory.view = filenameContainer
        window?.addTitlebarAccessoryViewController(filenameAccessory)

        positionLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        positionLabel.textColor = .secondaryLabelColor
        positionLabel.alignment = .center
        positionLabel.translatesAutoresizingMaskIntoConstraints = false
        positionLabel.widthAnchor.constraint(equalToConstant: 38).isActive = true
        positionLabel.isHidden = references.count == 1
        header.addArrangedSubview(positionLabel)
        for (button, symbol, label, action) in [
            (previousButton, "chevron.left", L10n.historyFilePreviewPrevious, #selector(previousItem)),
            (nextButton, "chevron.right", L10n.historyFilePreviewNext, #selector(nextItem))
        ] {
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .medium))
            button.imagePosition = .imageOnly
            button.bezelStyle = .toolbar
            button.isBordered = false
            button.contentTintColor = .secondaryLabelColor
            button.translatesAutoresizingMaskIntoConstraints = false
            button.setAccessibilityLabel(label)
            button.toolTip = label
            button.target = self
            button.action = action
            button.isEnabled = references.count > 1
            button.isHidden = references.count == 1
            header.addArrangedSubview(button)
            button.widthAnchor.constraint(equalToConstant: 30).isActive = true
            button.heightAnchor.constraint(equalToConstant: 24).isActive = true
        }
        updateTitlebarLayout()
        let accessory = NSTitlebarAccessoryViewController()
        accessory.layoutAttribute = .right
        accessory.view = header
        window?.addTitlebarAccessoryViewController(accessory)

        previewHost.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(previewHost)
        statusLabel.alignment = .center
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        previewHost.addSubview(statusLabel)
        retryButton.title = L10n.historyFilePreviewRetry
        retryButton.bezelStyle = .rounded
        retryButton.target = self
        retryButton.action = #selector(retryCurrentItem)
        retryButton.translatesAutoresizingMaskIntoConstraints = false
        previewHost.addSubview(retryButton)
        NSLayoutConstraint.activate([
            previewHost.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            previewHost.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            previewHost.topAnchor.constraint(equalTo: content.topAnchor),
            previewHost.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            statusLabel.centerXAnchor.constraint(equalTo: previewHost.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: previewHost.centerYAnchor, constant: -18),
            statusLabel.widthAnchor.constraint(lessThanOrEqualTo: previewHost.widthAnchor, constant: -48),
            retryButton.centerXAnchor.constraint(equalTo: previewHost.centerXAnchor),
            retryButton.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 14)
        ])
    }

    private func updateTitlebarLayout() {
        guard let window else { return }
        // Match HistoryPreviewWindowController's titlebar accessories.
        titlebarHeader.layoutSubtreeIfNeeded()
        let fittingSize = titlebarHeader.fittingSize
        titlebarHeader.frame = NSRect(
            x: 0, y: 0, width: ceil(fittingSize.width), height: max(24, ceil(fittingSize.height))
        )
        let availableWidth = window.frame.width - 148 - titlebarHeader.frame.width - 20
        let width = min(280, max(0, floor(availableWidth)))
        filenameContainer.isHidden = width < 48
        filenameContainer.frame = NSRect(
            x: 0, y: 0, width: width, height: 24
        )
    }

    func windowDidResize(_ notification: Notification) {
        updateTitlebarLayout()
    }

    @objc private func previousItem() { move(by: -1) }
    @objc private func nextItem() { move(by: 1) }
    @objc private func retryCurrentItem() { loadCurrentItem() }

    private func move(by offset: Int) {
        guard references.count > 1 else { return }
        currentIndex = (currentIndex + offset + references.count) % references.count
        loadCurrentItem()
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if modifiers == .command, event.charactersIgnoringModifiers?.lowercased() == "w" {
            close()
            return true
        }
        guard modifiers.isEmpty else { return false }
        switch Int(event.keyCode) {
        case kVK_Space, kVK_Escape:
            close()
        case kVK_LeftArrow:
            move(by: -1)
        case kVK_RightArrow:
            move(by: 1)
        default:
            return false
        }
        return true
    }

    private func loadCurrentItem() {
        guard !isClosed else { return }
        hasStartedLoading = true
        loadGeneration += 1
        let generation = loadGeneration
        sourceRequest?.cancel()
        reloadWorkItem?.cancel()
        stopSourceWatcher()
        clearCurrentPreview()
        let reference = references[currentIndex]
        setFilename(reference.name, path: reference.path)
        statusLabel.stringValue = L10n.historyFilePreviewLoading
        statusLabel.toolTip = nil
        statusLabel.isHidden = false
        retryButton.isHidden = true
        let request = HistoryImagePreviewRequest()
        sourceRequest = request
        HistoryFileReferences.transferQueue.addOperation { [weak self] in
            guard !request.isCancelled else { return }
            let url = reference.resolve()
            guard !request.isCancelled else { return }
            // Opening an event-only descriptor also stays off the main thread.
            let descriptor = url.map { open($0.path, O_EVTONLY | O_CLOEXEC) } ?? -1
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.isClosed, !request.isCancelled,
                      self.loadGeneration == generation else {
                    if descriptor >= 0 { Darwin.close(descriptor) }
                    return
                }
                self.sourceRequest = nil
                guard let url else {
                    self.statusLabel.stringValue = L10n.historyPanelSourceUnavailable
                    self.statusLabel.toolTip = L10n.historyPanelSourceUnavailableHint
                    self.retryButton.isHidden = false
                    return
                }
                self.setFilename(url.lastPathComponent, path: url.path)
                self.installSourceWatcher(descriptor: descriptor, generation: generation)
                if self.previewView == nil {
                    guard let view = QLPreviewView(frame: self.previewHost.bounds, style: .normal) else {
                        self.statusLabel.stringValue = L10n.historyFilePreviewUnavailable
                        self.retryButton.isHidden = false
                        return
                    }
                    view.autoresizingMask = [.width, .height]
                    view.shouldCloseWithWindow = false
                    view.autostarts = false
                    self.previewHost.addSubview(view)
                    self.previewView = view
                }
                self.previewView?.previewItem = HistoryQuickLookItem(url: url)
                self.previewView?.isHidden = false
                self.statusLabel.isHidden = true
            }
        }
    }

    private func setFilename(_ name: String, path: String) {
        filenameLabel.stringValue = name
        filenameLabel.toolTip = path
        positionLabel.stringValue = "\(currentIndex + 1) / \(references.count)"
        window?.title = name
        updateTitlebarLayout()
    }

    private func installSourceWatcher(descriptor: Int32, generation: Int) {
        guard descriptor >= 0 else { return }
        let watcher = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.delete, .rename, .write, .attrib, .revoke], queue: .main
        )
        watcher.setCancelHandler { Darwin.close(descriptor) }
        watcher.setEventHandler { [weak self] in
            guard let self, !self.isClosed, self.loadGeneration == generation else { return }
            self.pendingSourceEvents.formUnion(self.sourceWatcher?.data ?? [])
            self.reloadWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.loadGeneration == generation else { return }
                let events = self.pendingSourceEvents
                self.pendingSourceEvents = []
                // Quick Look reads can update access metadata. Reloading on every
                // attribute event would make the renderer restart itself forever.
                if events.subtracting(.attrib).isEmpty {
                    let reference = self.references[self.currentIndex]
                    HistoryFileReferences.transferQueue.addOperation { [weak self] in
                        let unavailable = reference.resolve() == nil
                        DispatchQueue.main.async { [weak self] in
                            guard let self, !self.isClosed,
                                  self.loadGeneration == generation, unavailable else { return }
                            self.loadCurrentItem()
                        }
                    }
                } else {
                    self.loadCurrentItem()
                }
            }
            self.reloadWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
        }
        sourceWatcher = watcher
        watcher.resume()
    }

    private func stopSourceWatcher() {
        sourceWatcher?.cancel()
        sourceWatcher = nil
        pendingSourceEvents = []
    }

    private func releasePreview() {
        previewView?.close()
        previewView?.removeFromSuperview()
        previewView = nil
    }

    private func clearCurrentPreview() {
        previewView?.previewItem = nil
        previewView?.isHidden = true
    }

    func windowDidBecomeKey(_ notification: Notification) {
        // Quick Look's remote view can participate in key-window changes while
        // loading. A valid watched item must not restart its own renderer here.
        if hasStartedLoading, !retryButton.isHidden { loadCurrentItem() }
    }

    override func close() {
        finish()
        super.close()
    }

    func windowWillClose(_ notification: Notification) { finish() }

    private func finish() {
        guard !isClosed else { return }
        isClosed = true
        loadGeneration += 1
        sourceRequest?.cancel()
        sourceRequest = nil
        reloadWorkItem?.cancel()
        reloadWorkItem = nil
        stopSourceWatcher()
        releasePreview()
        if Self.current === self { Self.current = nil }
        let callback = onClose
        onClose = nil
        callback?()
    }
}

private final class HistoryQuickLookItem: NSObject, QLPreviewItem {
    let previewItemURL: URL?
    let previewItemTitle: String?
    init(url: URL) {
        previewItemURL = url
        previewItemTitle = url.lastPathComponent
    }
}

private final class HistoryFileQuickLookPanel: NSPanel {
    var onKeyDown: ((NSEvent) -> Bool)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, onKeyDown?(event) == true { return }
        super.sendEvent(event)
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if onKeyDown?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }
}
