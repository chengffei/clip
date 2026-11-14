import AppKit
import UniformTypeIdentifiers

class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusBarController: StatusBarController!
    private var keyMonitor: KeyMonitor!
    private var overlayController: OverlayWindowController?
    private var recordingEngine: RecordingEngine?
    private var recordingHUDPanel: RecordingHUDPanel?
    private var recordingBorderPanel: RecordingBorderPanel?
    private var recordingScreenRect: NSRect = .zero
    private var recordingScreen: NSScreen?
    private var recordingCancelLocalMonitor: Any?
    private var recordingCancelGlobalMonitor: Any?
    private var recordingCancelRequested = false
    private var appInitialized = false
    private var suspendedEditDraft: OverlayWindowController.SuspendedEditDraft?
    private var pendingReopenSettingsWorkItem: DispatchWorkItem?
    private var startupDialogShown = false

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        FileLog.write("launch accessibility=\(AppPermissions.accessibilityGranted) screenRecording=\(AppPermissions.screenRecordingGranted)")
        Defaults.removeRetiredKeys()

        if AppPermissions.accessibilityGranted {
            // Start as soon as the ⌘⌘ trigger can work. Screen Recording is
            // requested on first capture; surface the permissions tab now if
            // it is still missing so the user is not left with a silent app.
            initializeApp()
            if !AppPermissions.screenRecordingGranted {
                configuredSettingsController().showAsSettings(focusingPermissions: true)
            }
        } else {
            showStartupDialog()
        }
    }

    func applicationDidChangeScreenParameters(_ notification: Notification) {
        guard appInitialized else { return }
        overlayController?.screenParametersDidChange()
        let displayIDs = Set(NSScreen.screens.compactMap { screen in
            screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? CGDirectDisplayID
        })
        ScreenSnapshotProvider.shared.invalidateAndPrewarm(displayIDs: displayIDs)
        OverlayWindowController.invalidateAndPrewarmPresentationSurfaces()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if appInitialized {
            scheduleSettingsOpenFromReopen()
        } else {
            showStartupDialog()
        }
        return false
    }

    private func showStartupDialog() {
        startupDialogShown = true
        let settingsController = configuredSettingsController()
        settingsController.showAsStartupDialog()
    }

    private func configuredSettingsController() -> SettingsWindowController {
        let settingsController = SettingsWindowController.shared
        settingsController.onMenuBarToggle = { [weak self] visible in
            self?.statusBarController?.setMenuBarVisible(visible)
        }
        settingsController.onLaunch = { [weak self] in
            self?.startupDialogShown = false
            self?.initializeApp()
        }
        return settingsController
    }

    private func initializeApp() {
        guard !appInitialized else { return }
        appInitialized = true

        OverlayWindowController.prewarmPresentationSurfaces()
        if AppPermissions.screenRecordingGranted {
            ScreenSnapshotProvider.shared.prewarm()
        }
        statusBarController = StatusBarController(
            onTakeScreenshot: { [weak self] in
                self?.handleTrigger(
                    triggerContext: CaptureTriggerContext(source: .menu)
                )
            },
            onTakeFullScreenScreenshot: { [weak self] in self?.handleFullScreenScreenshotTrigger() },
            onRecord: { [weak self] in self?.handleRecordingTrigger() },
            onCopyImageText: { [weak self] in self?.handleCopyImageTextTrigger() },
            onColorPicker: { [weak self] in self?.handleColorPickerTrigger() },
            onOpenSettings: { [weak self] in self?.openSettings() }
        )
        statusBarController.setMenuBarVisible(Defaults.showMenuBar)
        OCRService.warmUp()

        keyMonitor = KeyMonitor(
            onTrigger: { [weak self] context in
                guard let self else {
                    context.finish(.ignored)
                    return
                }
                self.handleDoubleTapCommand(triggerContext: context)
            },
            onCountdownTrigger: {}
        )

        NotificationCenter.default.addObserver(
            forName: .hotkeyDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applyHotkeyState()
        }
        applyHotkeyState()
    }

    private func applyHotkeyState() {
        if HotkeyManager.shared.isRecording {
            HotkeyManager.shared.unregister()
            unregisterNonScreenshotHotkeys()
            keyMonitor?.isEnabled = false
            return
        }

        if recordingEngine != nil {
            unregisterNonScreenshotHotkeys()
            keyMonitor?.isEnabled = true
            keyMonitor?.isRegularDoubleTapEnabled = !Defaults.hasCustomScreenshotHotkey
            if Defaults.hasCustomScreenshotHotkey {
                HotkeyManager.shared.register { [weak self] context in
                    guard let self else {
                        context.finish(.ignored)
                        return
                    }
                    self.stopRecordingAndSave()
                    context.finish(.rerouted)
                }
            } else {
                HotkeyManager.shared.unregister()
            }
            return
        }

        keyMonitor?.isEnabled = true
        if Defaults.hasCustomScreenshotHotkey {
            HotkeyManager.shared.register { [weak self] context in
                guard let self else {
                    context.finish(.ignored)
                    return
                }
                self.handleTrigger(fromShortcut: true, triggerContext: context)
            }
        } else {
            HotkeyManager.shared.unregister()
        }

        // Double-tap ⌘ does two jobs: it's the default screenshot trigger
        // when no custom screenshot hotkey is set, and the default
        // copy-to-clipboard trigger while an overlay is up (when no custom
        // clipboard hotkey is set). Keep it live whenever either path needs it.
        let needsDoubleTap = !Defaults.hasCustomScreenshotHotkey
            || (overlayController != nil && !Defaults.hasCustomClipboardHotkey)
        keyMonitor?.isRegularDoubleTapEnabled = needsDoubleTap

        if Defaults.hasCustomQuickPinHotkey {
            HotkeyManager.shared.registerQuickPin { [weak self] in
                self?.handleQuickPinTrigger()
            }
        } else {
            HotkeyManager.shared.unregisterQuickPin()
        }

        if Defaults.hasCustomTextRecognitionHotkey {
            HotkeyManager.shared.registerTextRecognition { [weak self] in
                self?.handleTextRecognitionTrigger()
            }
        } else {
            HotkeyManager.shared.unregisterTextRecognition()
        }

        if Defaults.hasCustomCopyImageTextHotkey {
            HotkeyManager.shared.registerCopyImageText { [weak self] in
                self?.handleCopyImageTextTrigger()
            }
        } else {
            HotkeyManager.shared.unregisterCopyImageText()
        }

        if Defaults.hasCustomRecordHotkey {
            HotkeyManager.shared.registerRecord { [weak self] in
                self?.handleRecordingTrigger()
            }
        } else {
            HotkeyManager.shared.unregisterRecord()
        }

        if Defaults.hasCustomFullScreenScreenshotHotkey {
            HotkeyManager.shared.registerFullScreenScreenshot { [weak self] in
                self?.handleFullScreenScreenshotTrigger()
            }
        } else {
            HotkeyManager.shared.unregisterFullScreenScreenshot()
        }

        if Defaults.hasCustomColorPickerHotkey {
            HotkeyManager.shared.registerColorPicker { [weak self] in
                self?.handleColorPickerTrigger()
            }
        } else {
            HotkeyManager.shared.unregisterColorPicker()
        }
    }

    private func unregisterNonScreenshotHotkeys() {
        HotkeyManager.shared.unregisterQuickPin()
        HotkeyManager.shared.unregisterTextRecognition()
        HotkeyManager.shared.unregisterCopyImageText()
        HotkeyManager.shared.unregisterRecord()
        HotkeyManager.shared.unregisterFullScreenScreenshot()
        HotkeyManager.shared.unregisterColorPicker()
    }

    /// KeyMonitor entry point for plain double-tap ⌘. While an overlay is
    /// active this is the default copy-to-clipboard hotkey; otherwise it falls
    /// through to the regular screenshot trigger.
    private func handleDoubleTapCommand(triggerContext: CaptureTriggerContext) {
        FileLog.write("doubleTap recording=\(recordingEngine != nil) overlay=\(overlayController != nil)")
        if recordingEngine != nil {
            stopRecordingAndSave()
            triggerContext.finish(.rerouted)
            return
        }
        if let overlay = overlayController {
            if !Defaults.hasCustomClipboardHotkey {
                overlay.confirmFromKeyboard()
            }
            triggerContext.finish(.rerouted)
            return
        }
        handleTrigger(fromShortcut: true, triggerContext: triggerContext)
    }

    func handleTrigger(
        fromShortcut: Bool = false,
        triggerContext: CaptureTriggerContext? = nil
    ) {
        let context = triggerContext ?? CaptureTriggerContext(
            source: fromShortcut ? .keyboardShortcut : .programmatic
        )
        context.mark(.handleTrigger)

        if recordingEngine != nil {
            stopRecordingAndSave()
            context.finish(.rerouted)
            return
        }
        guard overlayController == nil, recordingEngine == nil else {
            context.finish(.ignored)
            return
        }
        if resumeSuspendedEditIfAvailable() {
            context.finish(.rerouted)
            return
        }
        startCapture(
            triggerContext: context,
            onFirstFramePresented: nil
        )
    }

    func handleRecordingTrigger() {
        guard overlayController == nil, recordingEngine == nil else { return }
        guard ensureScreenRecordingAccess() else { return }
        let focusRestorer = SourceAppFocusRestorer.captureFrontmostApplication()
        overlayController = OverlayWindowController(
            postCaptureAction: .record,
            onRecordingSelection: { [weak self] rect, screen in
                self?.beginRecording(rect: rect, screen: screen)
            },
            onRequestFocusReturn: {
                focusRestorer.restore()
            },
            onComplete: { [weak self] finalImage in
                self?.handleEditCompletion(finalImage)
            }
        )
        overlayController?.activate()
        applyHotkeyState()
    }

    /// Select a screen region and pin it immediately after capture.
    func handlePinnedImageEditRequest(_ image: NSImage, beforePresent: () -> Void) -> Bool {
        guard overlayController == nil, recordingEngine == nil else { return false }
        beforePresent()

        guard let controller = ImageEditLauncher.launch(
            generatedImage: image,
            source: .pin,
            keepsEditorAcrossSpaces: Defaults.pinAcrossSpaces,
            onSuspend: { [weak self] draft in
                self?.handleEditSuspension(draft)
            },
            onComplete: { [weak self] finalImage in
                self?.handleEditCompletion(finalImage)
            }
        ) else {
            return false
        }

        overlayController = controller
        applyHotkeyState()
        return true
    }

    func handleQuickPinTrigger() {
        guard overlayController == nil, recordingEngine == nil else { return }
        startCapture(postCaptureAction: .quickPin)
    }

    func handleTextRecognitionTrigger() {
        guard overlayController == nil, recordingEngine == nil else { return }
        startCapture(postCaptureAction: .textRecognition)
    }

    func handleCopyImageTextTrigger() {
        guard overlayController == nil, recordingEngine == nil else { return }
        startCapture(postCaptureAction: .copyImageText)
    }

    func handleColorPickerTrigger() {
        guard overlayController == nil, recordingEngine == nil else { return }
        let focusRestorer = SourceAppFocusRestorer.captureFrontmostApplication()
        NSApp.activate(ignoringOtherApps: true)
        let didStart = ColorPickerRunner.shared.run(onFinished: {
            focusRestorer.restore()
        })
        if !didStart {
            focusRestorer.restore()
        }
    }

    private var fullScreenCaptureInFlight = false

    func handleFullScreenScreenshotTrigger() {
        guard overlayController == nil, recordingEngine == nil,
              !fullScreenCaptureInFlight else { return }
        let focusRestorer = SourceAppFocusRestorer.captureFrontmostApplication()
        let cursorPoint = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(cursorPoint) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen,
              let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        else {
            ToastWindow.show(message: L10n.fullScreenScreenshotFailed)
            return
        }
        // The capture enumerates shareable content and takes the screenshot,
        // 100 to 300 ms; waiting on it here froze the run loop for that long
        // on every full-screen shot. Capture off the main thread, then open
        // the editor.
        fullScreenCaptureInFlight = true
        let rect = CGDisplayBounds(displayID)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let image = ScreenCapturer.capture(rect: rect, screen: screen)
            DispatchQueue.main.async {
                guard let self else { return }
                self.fullScreenCaptureInFlight = false
                self.finishFullScreenScreenshot(image, focusRestorer: focusRestorer)
            }
        }
    }

    private func finishFullScreenScreenshot(_ image: NSImage?, focusRestorer: SourceAppFocusRestorer) {
        guard overlayController == nil, recordingEngine == nil else { return }
        guard let image,
              let controller = ImageEditLauncher.launch(
                generatedImage: image,
                source: .fullScreen,
                onRequestFocusReturn: {
                    focusRestorer.restore()
                },
                onSuspend: { [weak self] draft in
                    self?.handleEditSuspension(draft)
                },
                onComplete: { [weak self] finalImage in
                    self?.handleEditCompletion(finalImage)
                }
              )
        else {
            ToastWindow.show(message: L10n.fullScreenScreenshotFailed)
            return
        }

        overlayController = controller
        applyHotkeyState()
    }

    func startCapture(
        postCaptureAction: OverlayWindowController.PostCaptureAction = .edit,
        triggerContext: CaptureTriggerContext? = nil,
        onFirstFramePresented: (() -> Void)? = nil
    ) {
        let context = triggerContext ?? CaptureTriggerContext(source: .programmatic)
        context.mark(.startCapture)
        guard overlayController == nil, recordingEngine == nil else {
            context.finish(.ignored)
            return
        }
        guard ensureScreenRecordingAccess() else {
            context.finish(.ignored)
            return
        }
        let focusRestorer = SourceAppFocusRestorer.captureFrontmostApplication()
        overlayController = OverlayWindowController(
            postCaptureAction: postCaptureAction,
            triggerContext: context,
            onFirstFramePresented: onFirstFramePresented,
            onRecordingSelection: { [weak self] rect, screen in
                self?.beginRecording(rect: rect, screen: screen)
            },
            onRequestFocusReturn: {
                focusRestorer.restore()
            },
            onSuspend: { [weak self] draft in
                self?.handleEditSuspension(draft)
            },
            onComplete: { [weak self] finalImage in
                self?.handleEditCompletion(finalImage)
            }
        )
        overlayController?.activate()
        applyHotkeyState()
    }

    private func handleEditCompletion(_ finalImage: NSImage?) {
        if let finalImage = finalImage {
            let quality = Defaults.screenshotClipboardQuality
            if quality.usesLossyCompression {
                ToastWindow.show(message: L10n.screenshotQualityCompressingClipboard, duration: 600)
            }
            ImageOutputEncoder.encodeClipboardAsync(image: finalImage, quality: quality) { result in
                if quality.usesLossyCompression {
                    ToastWindow.dismiss()
                }
                switch result {
                case .failure:
                    ToastWindow.show(message: L10n.screenshotCompressionFailed, duration: 3.0)
                case .success(let output):
                    ClipboardManager.copyToClipboard(imageOutput: output)
                    ToastWindow.show()
                }
            }
        }
        overlayController = nil
        applyHotkeyState()
    }

    private func handleEditSuspension(_ draft: OverlayWindowController.SuspendedEditDraft) {
        suspendedEditDraft = draft
        overlayController = nil
        applyHotkeyState()
        ToastWindow.show(
            message: L10n.editSuspendedToast,
            on: screen(for: draft),
            duration: 3.0
        )
    }

    private func resumeSuspendedEditIfAvailable() -> Bool {
        guard let draft = suspendedEditDraft else { return false }
        let focusRestorer = SourceAppFocusRestorer.captureFrontmostApplication()
        let controller = OverlayWindowController(
            suspendedDraft: draft,
            onRecordingSelection: { [weak self] rect, screen in
                self?.beginRecording(rect: rect, screen: screen)
            },
            onRequestFocusReturn: {
                focusRestorer.restore()
            },
            onSuspend: { [weak self] draft in
                self?.handleEditSuspension(draft)
            },
            onComplete: { [weak self] finalImage in
                self?.handleEditCompletion(finalImage)
            }
        )
        suspendedEditDraft = nil
        overlayController = controller
        controller.activate()
        applyHotkeyState()
        return true
    }

    private func screen(for draft: OverlayWindowController.SuspendedEditDraft) -> NSScreen? {
        if let displayID = draft.screenDisplayID,
           let screen = NSScreen.screens.first(where: {
               ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == displayID
           }) {
            return screen
        }
        return NSScreen.screens.first(where: { $0.frame == draft.screenFrame }) ?? NSScreen.main
    }

    private func beginRecording(rect: NSRect, screen: NSScreen) {
        guard recordingEngine == nil else { return }

        recordingScreenRect = rect
        recordingScreen = screen
        recordingCancelRequested = false

        let borderPanel = RecordingBorderPanel(screen: screen)
        borderPanel.setSelectionRect(rect)
        borderPanel.orderFrontRegardless()
        recordingBorderPanel = borderPanel

        let hudPanel = RecordingHUDPanel()
        hudPanel.update(elapsedSeconds: 0)
        hudPanel.positionOnScreen(relativeTo: rect, screen: screen)
        hudPanel.onStopRecording = { [weak self] in
            self?.stopRecordingAndSave()
        }
        hudPanel.onPauseRecording = { [weak self] in
            self?.recordingEngine?.pauseRecording()
        }
        hudPanel.onResumeRecording = { [weak self] in
            self?.recordingEngine?.resumeRecording()
        }
        hudPanel.orderFrontRegardless()
        recordingHUDPanel = hudPanel

        let engine = RecordingEngine()
        engine.onProgress = { [weak self] seconds in
            self?.updateRecordingHUD(seconds: seconds)
        }
        engine.onPauseChanged = { [weak self] paused in
            self?.recordingHUDPanel?.setPaused(paused)
        }
        engine.onCompletion = { [weak self] url, error in
            self?.finishRecording(url: url, error: error)
        }
        recordingEngine = engine
        installRecordingCancelMonitors()
        applyHotkeyState()

        let excludedWindows = [
            recordingBorderPanel.map { CGWindowID($0.windowNumber) },
            recordingHUDPanel.map { CGWindowID($0.windowNumber) },
        ].compactMap { $0 } + ToastWindow.captureExcludedWindowNumbers
        engine.startRecording(
            rect: rect,
            screen: screen,
            excludeWindowNumbers: excludedWindows
        )
    }

    private func updateRecordingHUD(seconds: Int) {
        recordingHUDPanel?.update(elapsedSeconds: seconds)
        if let screen = recordingScreen, recordingHUDPanel?.userHasDragged != true {
            recordingHUDPanel?.positionOnScreen(relativeTo: recordingScreenRect, screen: screen)
        }
    }

    private func finishRecording(url: URL?, error: Error?) {
        let wasCancelled = recordingCancelRequested
        recordingCancelRequested = false
        stopRecordingUI()

        if wasCancelled {
            if let url {
                try? FileManager.default.removeItem(at: url)
            }
            ToastWindow.show(message: L10n.recordingCancelled)
            return
        }

        if let error {
            ToastWindow.show(message: L10n.recordingFailed(error.localizedDescription), duration: 3.5)
            return
        }

        guard let url else {
            ToastWindow.show(message: L10n.recordingFailed(RecordingEngine.RecordingError.noFrames.localizedDescription), duration: 3.5)
            return
        }

        promptToSaveRecording(tmpURL: url)
    }

    private func stopRecordingUI() {
        removeRecordingCancelMonitors()
        recordingHUDPanel?.close()
        recordingHUDPanel = nil
        recordingBorderPanel?.close()
        recordingBorderPanel = nil
        recordingEngine = nil
        recordingScreenRect = .zero
        recordingScreen = nil
        applyHotkeyState()
    }

    private func stopRecordingAndSave() {
        guard let recordingEngine else { return }
        recordingEngine.stopRecording()
    }

    private func cancelRecordingFromKeyboard() {
        guard let recordingEngine, !recordingCancelRequested else { return }
        switch recordingEngine.state {
        case .recording, .paused:
            break
        case .idle, .stopping:
            return
        }
        recordingCancelRequested = true
        recordingEngine.cancelRecording()
    }

    private func installRecordingCancelMonitors() {
        removeRecordingCancelMonitors()
        recordingCancelLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if Self.isPlainEscape(event) {
                self?.cancelRecordingFromKeyboard()
                return nil
            }
            return event
        }
        recordingCancelGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if Self.isPlainEscape(event) {
                self?.cancelRecordingFromKeyboard()
            }
        }
    }

    private func removeRecordingCancelMonitors() {
        if let monitor = recordingCancelLocalMonitor {
            NSEvent.removeMonitor(monitor)
            recordingCancelLocalMonitor = nil
        }
        if let monitor = recordingCancelGlobalMonitor {
            NSEvent.removeMonitor(monitor)
            recordingCancelGlobalMonitor = nil
        }
    }

    private static func isPlainEscape(_ event: NSEvent) -> Bool {
        let activeModifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        return event.keyCode == 53 && activeModifiers.isEmpty
    }

    private func promptToSaveRecording(tmpURL: URL) {
        if Defaults.askSaveLocation {
            promptForRecordingSaveLocation(tmpURL: tmpURL)
            return
        }
        if let format = Defaults.recordingSavePreference.format {
            saveRecordingToConfiguredDirectory(tmpURL: tmpURL, format: format)
            return
        }

        promptToChooseRecordingFormat(tmpURL: tmpURL)
    }

    private func promptToChooseRecordingFormat(tmpURL: URL) {
        var selectedFormat = Defaults.recordingSaveFormat
        let alert = NSAlert()
        alert.messageText = L10n.recordingFormatChoiceTitle
        alert.informativeText = L10n.recordingFormatChoiceMessage
        alert.alertStyle = .informational
        alert.addButton(withTitle: L10n.saveRecordingPrompt)
        alert.addButton(withTitle: L10n.shortcutCancel)
        alert.accessoryView = RecordingSaveAccessoryView(initialFormat: selectedFormat) { format in
            selectedFormat = format
        }

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else {
            try? FileManager.default.removeItem(at: tmpURL)
            return
        }

        Defaults.recordingSaveFormat = selectedFormat
        saveRecordingToConfiguredDirectory(tmpURL: tmpURL, format: selectedFormat)
    }

    /// Save panel for recordings. Cancelling still keeps the take in the
    /// recording folder: unlike a screenshot there is no editor to return to.
    private func promptForRecordingSaveLocation(tmpURL: URL) {
        let fixedFormat = Defaults.recordingSavePreference.format
        var format = fixedFormat ?? Defaults.recordingSaveFormat
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.directoryURL = Defaults.recordingSaveDirectory
        panel.allowedContentTypes = [UTType(filenameExtension: format.fileExtension) ?? .data]
        panel.nameFieldStringValue = FilenameTemplate.recordingFileName(fileExtension: format.fileExtension, consumeCounters: false)
        if fixedFormat == nil {
            panel.accessoryView = RecordingSaveAccessoryView(initialFormat: format) { [weak panel] newFormat in
                format = newFormat
                panel?.allowedContentTypes = [UTType(filenameExtension: newFormat.fileExtension) ?? .data]
            }
        }

        NSApp.activate(ignoringOtherApps: true)
        let response = panel.runModal()
        if fixedFormat == nil {
            Defaults.recordingSaveFormat = format
        }
        guard response == .OK, let url = panel.url else {
            saveRecordingToConfiguredDirectory(tmpURL: tmpURL, format: format)
            return
        }
        saveRecording(tmpURL: tmpURL, destination: url, format: format)
    }

    private func saveRecordingToConfiguredDirectory(tmpURL: URL, format: ScreenRecordingFormat) {
        do {
            let filename = FilenameTemplate.recordingFileName(fileExtension: format.fileExtension)
            let destination = try SaveDestination.uniqueFile(in: Defaults.recordingSaveDirectory, fileName: filename)
            saveRecording(tmpURL: tmpURL, destination: destination, format: format)
        } catch {
            try? FileManager.default.removeItem(at: tmpURL)
            ToastWindow.show(message: L10n.recordingFailed(error.localizedDescription), duration: 3.5)
        }
    }

    private func saveRecording(tmpURL: URL, destination: URL, format: ScreenRecordingFormat) {
        switch format {
        case .mp4:
            do {
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: tmpURL, to: destination)
                showSavedRecording(destination)
            } catch {
                ToastWindow.show(message: L10n.recordingFailed(error.localizedDescription), duration: 3.5)
            }
        case .gif:
            ToastWindow.show(message: L10n.recordingExportingGIF, duration: 600)
            RecordingExporter.exportGIF(from: tmpURL, to: destination) { result in
                ToastWindow.dismiss()
                switch result {
                case .success:
                    try? FileManager.default.removeItem(at: tmpURL)
                    self.showSavedRecording(destination)
                case .failure(let error):
                    ToastWindow.show(message: L10n.recordingFailed(error.localizedDescription), duration: 3.5)
                    NSWorkspace.shared.activateFileViewerSelecting([tmpURL])
                }
            }
        }
    }

    private func showSavedRecording(_ destination: URL) {
        let directoryPath = SaveDestination.displayPath(destination.deletingLastPathComponent())
        ToastWindow.show(message: L10n.recordingSaved(to: directoryPath))
        if Defaults.autoRevealSavedFiles {
            NSWorkspace.shared.activateFileViewerSelecting([destination])
        }
    }

    private func openSettings() {
        configuredSettingsController().showAsSettings()
    }

    /// True when Screen Recording is granted. Otherwise asks the system (which
    /// registers Clip in the Screen Recording list and prompts the first time)
    /// and opens the permissions tab, so a trigger never fails silently.
    @discardableResult
    private func ensureScreenRecordingAccess() -> Bool {
        if AppPermissions.screenRecordingGranted { return true }
        let granted = CGRequestScreenCaptureAccess()
        FileLog.write("screenRecording missing, request returned \(granted)")
        if granted { return true }
        configuredSettingsController().showAsSettings(focusingPermissions: true)
        return false
    }

    private func scheduleSettingsOpenFromReopen() {
        cancelPendingReopenSettings()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.overlayController == nil else { return }
            self.openSettings()
        }
        pendingReopenSettingsWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: workItem)
    }

    private func cancelPendingReopenSettings() {
        pendingReopenSettingsWorkItem?.cancel()
        pendingReopenSettingsWorkItem = nil
    }

}

private final class RecordingSaveAccessoryView: NSView {
    private static let labelTrailingInset: CGFloat = 170
    private let popup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let onFormatChanged: (ScreenRecordingFormat) -> Void

    init(initialFormat: ScreenRecordingFormat, onFormatChanged: @escaping (ScreenRecordingFormat) -> Void) {
        self.onFormatChanged = onFormatChanged
        super.init(frame: NSRect(x: 0, y: 0, width: 460, height: 32))

        let label = NSTextField(labelWithString: L10n.recordingFormatLabel)
        label.translatesAutoresizingMaskIntoConstraints = false

        popup.translatesAutoresizingMaskIntoConstraints = false
        for format in ScreenRecordingFormat.allCases {
            popup.addItem(withTitle: format.displayName)
            popup.lastItem?.representedObject = format.rawValue
        }
        popup.selectItem(withTitle: initialFormat.displayName)
        popup.target = self
        popup.action = #selector(formatDidChange)

        addSubview(label)
        addSubview(popup)

        NSLayoutConstraint.activate([
            label.trailingAnchor.constraint(equalTo: leadingAnchor, constant: Self.labelTrailingInset),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),

            popup.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 8),
            popup.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            popup.centerYAnchor.constraint(equalTo: centerYAnchor),
            popup.widthAnchor.constraint(greaterThanOrEqualToConstant: 140),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func formatDidChange() {
        guard let raw = popup.selectedItem?.representedObject as? String,
              let format = ScreenRecordingFormat(rawValue: raw)
        else {
            return
        }
        onFormatChanged(format)
    }
}
