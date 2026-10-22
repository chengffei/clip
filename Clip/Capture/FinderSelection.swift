import AppKit
import UniformTypeIdentifiers

enum FinderSelection {
    /// Returns the URL when Finder has exactly one image file selected,
    /// otherwise nil. Triggers the Apple Events permission prompt on first
    /// use; on permission denial or any failure, returns nil.
    static func currentImageFileURL() -> URL? {
        let urls = currentSelectionURLs()
        guard urls.count == 1, let url = urls.first else { return nil }
        guard isImage(url) else { return nil }
        return url
    }

    /// Returns every image file currently selected in Finder, preserving
    /// Finder's selection order and ignoring non-image files.
    static func currentImageFileURLs() -> [URL] {
        currentSelectionURLs().filter(isImage)
    }

    /// Returns every regular file currently selected in Finder, preserving
    /// Finder's selection order and excluding folders or other containers.
    static func currentFileURLs() -> [URL] {
        currentSelectionURLs().filter { url in
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            return values?.isRegularFile == true
        }
    }

    /// Clears Finder's current selection. Used by pin mode so the same source
    /// is not re-pinned. Silently no-ops on any failure.
    static func clearSelection() {
        let source = """
        tell application "Finder"
            set selection to {}
        end tell
        """
        guard let script = NSAppleScript(source: source) else { return }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
    }

    private static func currentSelectionURLs() -> [URL] {
        let source = """
        tell application "Finder"
            set sel to selection
            set out to {}
            repeat with f in sel
                try
                    set end of out to POSIX path of (f as alias)
                end try
            end repeat
            return out
        end tell
        """

        guard let script = NSAppleScript(source: source) else { return [] }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if error != nil { return [] }

        var urls: [URL] = []
        // AppleScript returns a list descriptor; items are 1-indexed.
        let count = result.numberOfItems
        if count == 0 { return [] }
        for i in 1...count {
            if let path = result.atIndex(i)?.stringValue {
                urls.append(URL(fileURLWithPath: path))
            }
        }
        return urls
    }

    private static func isImage(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.contentTypeKey])
        guard let type = values?.contentType else { return false }
        return type.conforms(to: .image)
    }
}
