import AppKit

/// Shared source of truth for the selectable annotation font families.
///
/// Both the editor's text sub-toolbar and the settings window read their list
/// from here so the two surfaces can never drift apart. The family list and the
/// rendered menu titles are built lazily and cached, because
/// `availableFontFamilies` plus one `NSFont` per family is expensive enough to
/// be felt when a HUD menu is opened.
enum FontCatalog {
    /// Point size used to render the font-preview menu titles.
    private static let previewPointSize: CGFloat = 13

    private static var cachedFamilies: [String]?
    private static var cachedInstalled: Set<String>?
    private static var cachedTitles: [String: NSAttributedString] = [:]

    /// Installed font families, hidden (dot-prefixed) system faces removed and
    /// sorted by their localized display name.
    static var families: [String] {
        if let cachedFamilies { return cachedFamilies }
        let list = NSFontManager.shared.availableFontFamilies
            .filter { !$0.hasPrefix(".") }
            .sorted { displayName(for: $0).localizedStandardCompare(displayName(for: $1)) == .orderedAscending }
        cachedFamilies = list
        cachedInstalled = Set(list)
        return list
    }

    /// Whether `family` is installed. Answers from the sorted list when it
    /// already exists; otherwise asks for that one family only, because
    /// building the whole list (every family, sorted by localized name) took
    /// hundreds of milliseconds on the main thread when the editor opened
    /// and read `Defaults.textFontName`.
    static func isInstalled(_ family: String) -> Bool {
        if let cachedInstalled { return cachedInstalled.contains(family) }
        guard !family.hasPrefix(".") else { return false }
        return NSFontManager.shared.availableMembers(ofFontFamily: family)?.isEmpty == false
    }

    /// Localized family name, e.g. "PingFang SC" -> "苹方-简" in Chinese.
    static func displayName(for family: String) -> String {
        NSFontManager.shared.localizedName(forFamily: family, face: nil)
    }

    /// Title for the currently selected family. An unknown or uninstalled
    /// family falls back to the system-default label, matching the font
    /// resolution in `TextAnnotation.font(named:size:)`.
    static func title(for family: String?) -> String {
        guard let family, isInstalled(family) else { return L10n.textFontSystemDefault }
        return displayName(for: family)
    }

    /// Menu title rendered in the family's own face so the list previews itself.
    static func previewTitle(for family: String) -> NSAttributedString {
        if let cached = cachedTitles[family] { return cached }
        let name = displayName(for: family)
        let font = TextAnnotation.font(named: family, size: previewPointSize)
        let attributed = NSAttributedString(
            string: name,
            attributes: [.font: font]
        )
        cachedTitles[family] = attributed
        return attributed
    }

}
