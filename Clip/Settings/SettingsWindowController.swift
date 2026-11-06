import AppKit

private final class SettingsWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let commandModifiers: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
        let modifiers = event.modifierFlags.intersection(commandModifiers)
        if modifiers == .command,
           event.charactersIgnoringModifiers?.lowercased() == "w" {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    var onMenuBarToggle: ((Bool) -> Void)?
    var onLaunch: (() -> Void)?

    private var settingsView: SettingsView!
    private var isStartup = true

    /// Content width; panes lay out their grouped rows to this.
    static let contentWidth: CGFloat = 680

    /// A standard settings window (Apple HIG, Settings): a non-customizable
    /// toolbar switches panes and always shows the active one, the title is
    /// the pane's name, minimize and zoom stay dimmed, and the height follows
    /// the pane.
    private init() {
        let window = SettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.contentWidth, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.settingsTitle
        window.toolbarStyle = .preference
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = Brand.canvas
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .normal

        super.init(window: window)

        let toolbar = NSToolbar(identifier: "ClipSettingsToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar

        NotificationCenter.default.addObserver(forName: .languageDidChange, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            for item in self.window?.toolbar?.items ?? [] {
                if let tab = SettingsTab(rawValue: item.itemIdentifier.rawValue) {
                    item.label = tab.title
                    item.toolTip = tab.title
                }
            }
            self.window?.title = self.settingsView.currentTab.title
        }

        settingsView = SettingsView(frame: NSRect(x: 0, y: 0, width: Self.contentWidth, height: 520), isStartup: true)
        settingsView.onTabChange = { [weak self] tab in
            guard let self, let window = self.window else { return }
            window.toolbar?.selectedItemIdentifier = NSToolbarItem.Identifier(tab.rawValue)
            window.title = tab.title
            self.fitWindowToPane(animate: window.isVisible)
        }
        settingsView.onMenuBarToggle = { [weak self] visible in
            self?.onMenuBarToggle?(visible)
        }
        settingsView.onLaunch = { [weak self] in
            self?.isStartup = false
            self?.settingsView.setStartupMode(false)
            self?.window?.close()
            self?.onLaunch?()
        }
        window.contentView = settingsView
        window.initialFirstResponder = settingsView
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showAsStartupDialog() {
        if !AppPermissions.screenRecordingGranted {
            _ = CGRequestScreenCaptureAccess()
        }
        isStartup = true
        settingsView.setStartupMode(true)
        fitWindowToPane(animate: false)
        window?.center()
        resetInitialFocus()
        showWindow(nil)
        resetInitialFocus()
        NSApp.activate(ignoringOtherApps: true)
    }

    func showAsSettings(focusingPermissions: Bool? = nil) {
        isStartup = false
        settingsView.setStartupMode(false)
        let shouldFocusPermissions = focusingPermissions ?? !AppPermissions.allRequiredGranted
        if shouldFocusPermissions {
            settingsView.showPermissionsTab()
        }
        fitWindowToPane(animate: false)
        resetInitialFocus()
        showWindow(nil)
        resetInitialFocus()
        NSApp.activate(ignoringOtherApps: true)
    }


    private func resetInitialFocus() {
        window?.initialFirstResponder = settingsView
        window?.makeFirstResponder(settingsView)
    }

    /// Grows or shrinks the window to the current pane, keeping its top edge
    /// put; tall panes (shortcuts, toolbar) scroll past 640 pt.
    private func fitWindowToPane(animate: Bool) {
        guard let window else { return }
        let height = min(max(settingsView.preferredPaneHeight, 220), 640)
        let content = NSRect(x: 0, y: 0, width: Self.contentWidth, height: height)
        var frame = window.frameRect(forContentRect: content)
        frame.origin.x = window.frame.minX
        frame.origin.y = window.frame.maxY - frame.height
        guard abs(frame.height - window.frame.height) > 0.5 || abs(frame.width - window.frame.width) > 0.5 else { return }
        window.setFrame(frame, display: true, animate: animate && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }
}

extension SettingsWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        settingsView.cancelToolbarShortcutRecording()
        settingsView.cancelShortcutRecording()
        settingsView.cancelQuickPinShortcutRecording()
        settingsView.cancelClipboardShortcutRecording()
        settingsView.cancelFileSaveShortcutRecording()
        settingsView.closePermissionFlowPanel()
        guard isStartup else { return }
        // The startup dialog is a gate. Closing it without pressing Launch
        // means the app was never initialized — no menu bar, no key monitor,
        // no UI. Keeping the process alive would make it a zombie: the next
        // icon click only sends a reopen event that nothing handles, so the
        // app appears not to start. Quit instead, so re-clicking the icon
        // performs a clean launch. (The Launch path clears isStartup first,
        // so it never reaches here.)
        NSApp.terminate(nil)
    }
}

extension SettingsWindowController: NSToolbarDelegate {
    private var tabIdentifiers: [NSToolbarItem.Identifier] {
        SettingsTab.allCases.map { NSToolbarItem.Identifier($0.rawValue) }
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { tabIdentifiers }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { tabIdentifiers }
    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { tabIdentifiers }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let tab = SettingsTab(rawValue: id.rawValue) else { return nil }
        let item = NSToolbarItem(itemIdentifier: id)
        item.label = tab.title
        item.toolTip = tab.title
        item.image = NSImage(systemSymbolName: tab.iconName, accessibilityDescription: tab.title)
        item.target = self
        item.action = #selector(toolbarTabClicked(_:))
        return item
    }

    @objc private func toolbarTabClicked(_ sender: NSToolbarItem) {
        guard let tab = SettingsTab(rawValue: sender.itemIdentifier.rawValue) else { return }
        settingsView.selectTab(tab)
    }
}
