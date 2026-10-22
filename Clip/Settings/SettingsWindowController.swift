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

    private init() {
        let window = SettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 600),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.settingsTitle
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = Brand.ink
        window.isMovableByWindowBackground = true
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .normal

        super.init(window: window)

        NotificationCenter.default.addObserver(forName: .languageDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.window?.title = L10n.settingsTitle
        }

        settingsView = SettingsView(frame: NSRect(x: 0, y: 0, width: 820, height: 600), isStartup: true)
        settingsView.onMenuBarToggle = { [weak self] visible in
            self?.onMenuBarToggle?(visible)
        }
        settingsView.onLaunch = { [weak self] in
            self?.isStartup = false
            self?.settingsView.setStartupMode(false)
            self?.resizeWindow(height: 600)
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
        resizeWindow(height: 640)
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
        resizeWindow(height: 600)
        resetInitialFocus()
        showWindow(nil)
        resetInitialFocus()
        NSApp.activate(ignoringOtherApps: true)
    }

    func dismissStartupDialogForExternalOpen() {
        guard isStartup else { return }
        isStartup = false
        settingsView.setStartupMode(false)
        resizeWindow(height: 600)
        window?.close()
    }

    private func resetInitialFocus() {
        window?.initialFirstResponder = settingsView
        window?.makeFirstResponder(settingsView)
    }

    private func resizeWindow(height: CGFloat) {
        guard let window = window else { return }
        var frame = window.frame
        let delta = height - frame.size.height
        frame.size.height = height
        frame.origin.y -= delta
        window.setFrame(frame, display: true, animate: false)
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
