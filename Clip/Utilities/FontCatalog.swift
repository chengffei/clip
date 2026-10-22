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

    static func isInstalled(_ family: String) -> Bool {
        _ = families
        return cachedInstalled?.contains(family) ?? false
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

    /// Drops the caches so a newly installed or removed family is picked up.
    static func invalidate() {
        cachedFamilies = nil
        cachedInstalled = nil
        cachedTitles.removeAll()
    }
}
