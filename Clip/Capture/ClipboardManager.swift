import AppKit

private let skipClipboardHistoryPasteboardType = NSPasteboard.PasteboardType(
    "cn.skyrin.capcap.skip-clipboard-text-history"
)

enum ClipboardColorParser {
    static func normalizedHex(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("#") else { return nil }

        let digits = trimmed.dropFirst()
        guard digits.count == 6, UInt32(digits, radix: 16) != nil else { return nil }
        return "#" + digits.uppercased()
    }
}

struct ClipboardManager {
    static func copyToClipboard(
        image: NSImage,
        pasteboard: NSPasteboard = .general
    ) {
        pasteboard.clearContents()

        if let pngData = image.pngDataPreservingBacking() {
            pasteboard.setData(pngData, forType: .png)
        }

        if let tiffData = image.tiffDataPreservingBacking() {
            pasteboard.setData(tiffData, forType: .tiff)
        }
    }

    static func copyToClipboard(imageOutput: EncodedClipboardImageOutput) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(imageOutput.primary.data, forType: imageOutput.primary.pasteboardType)
        if let tiffData = imageOutput.tiffData {
            pasteboard.setData(tiffData, forType: .tiff)
        }
    }

    static func copyToClipboard(text: String, skipHistory: Bool = false) {
        writeTextToClipboard(text, skipHistory: skipHistory)
    }

    static func copyColorToClipboard(hex: String) {
        guard let normalizedHex = ClipboardColorParser.normalizedHex(from: hex) else {
            writeTextToClipboard(hex)
            return
        }
        writeTextToClipboard(normalizedHex, skipHistory: true)
    }

    static func copyHistoryTextToClipboard(_ text: String) {
        writeTextToClipboard(text, skipHistory: true)
    }

    @discardableResult
    static func copyHistoryFilesToClipboard(_ urls: [URL]) -> Bool {
        guard !urls.isEmpty else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.writeObjects(urls.map { $0 as NSURL }) else { return false }
        pasteboard.setString("1", forType: skipClipboardHistoryPasteboardType)
        return true
    }

    private static func writeTextToClipboard(_ text: String, skipHistory: Bool = false) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        if skipHistory {
            pasteboard.setString("1", forType: skipClipboardHistoryPasteboardType)
        }
    }
}

final class ClipboardTextHistoryMonitor: NSObject {
    private let pasteboard: NSPasteboard
    private var timer: Timer?
    private var lastChangeCount = 0
    private var isStarted = false

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
        super.init()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        timer?.invalidate()
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        lastChangeCount = pasteboard.changeCount
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(cacheSettingChanged),
            name: .clipboardTextCacheEnabledDidChange,
            object: nil
        )
        updateTimerState()
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        NotificationCenter.default.removeObserver(self)
        stopTimer()
    }

    @objc private func cacheSettingChanged() {
        lastChangeCount = pasteboard.changeCount
        updateTimerState()
    }

    private func updateTimerState() {
        if Defaults.clipboardTextCacheEnabled {
            startTimer()
        } else {
            stopTimer()
        }
    }

    private func startTimer() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.pollPasteboard()
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func pollPasteboard() {
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount
        guard Defaults.clipboardTextCacheEnabled,
              pasteboard.availableType(from: [skipClipboardHistoryPasteboardType]) == nil else { return }

        // Inspect declared file types before requesting a text representation.
        // A pasted path string must remain text even if it names a real file.
        let legacyFiles = NSPasteboard.PasteboardType("NSFilenamesPboardType")
        if pasteboard.availableType(from: [.fileURL, legacyFiles]) != nil {
            var urls = pasteboard.readObjects(forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
            if urls.isEmpty, let paths = pasteboard.propertyList(forType: legacyFiles) as? [String] {
                urls = paths.map { URL(fileURLWithPath: $0) }
            }
            guard pasteboard.changeCount == changeCount else { return }
            HistoryManager.shared.addFileReferences(urls)
            return
        }
        // Virtual/promised files have no stable source URL. Never record their
        // accompanying filename or TIFF icon as an ordinary history item.
        let promisedTypes = ["com.apple.pasteboard.promised-file-url", "com.apple.NSFilesPromisePboardType"]
        if pasteboard.types?.contains(where: { promisedTypes.contains($0.rawValue) }) == true { return }
        guard
              let text = pasteboard.string(forType: .string),
              !text.isEmpty, pasteboard.changeCount == changeCount else { return }
        if Defaults.historyCacheEnabled,
           let hex = ClipboardColorParser.normalizedHex(from: text) {
            HistoryManager.shared.addColor(hex: hex)
        } else {
            HistoryManager.shared.addText(text)
        }
    }
}
