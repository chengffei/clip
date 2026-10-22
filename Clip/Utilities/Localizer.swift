import Foundation

/// Resolves UI strings from the per-language `.lproj` bundles shipped inside
/// `capcap.app/Contents/Resources/`.
///
/// The app has an in-app language picker, so we can't lean on
/// `NSLocalizedString` — that keys off the *system* locale. Instead we load the
/// `.lproj` bundle for the user's chosen `AppLanguage` explicitly and look keys
/// up there, which also lets language changes take effect live.
enum Localizer {
    /// Sentinel returned by `localizedString` when a key is absent — distinct
    /// from any real value so we can detect misses and fall back.
    private static let missing = "\u{0}capcap.l10n.missing\u{0}"

    /// (language, resolved bundle) — recomputed only when the language changes.
    private static var cache: (lang: AppLanguage, bundle: Bundle)?

    private static func bundle(for lang: AppLanguage) -> Bundle {
        if let cache, cache.lang == lang { return cache.bundle }
        let resolved: Bundle
        if let path = Bundle.main.path(forResource: lang.lprojName, ofType: "lproj"),
           let lproj = Bundle(path: path) {
            resolved = lproj
        } else if let sourceLproj = sourceTreeBundle(for: lang) {
            resolved = sourceLproj
        } else {
            // Running unbundled (e.g. `swift run`) — no .lproj on disk.
            resolved = .main
        }
        cache = (lang, resolved)
        return resolved
    }

    private static func sourceTreeBundle(for lang: AppLanguage) -> Bundle? {
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources")
            .appendingPathComponent("\(lang.lprojName).lproj")
        return Bundle(url: url)
    }

    /// The localized string for `key` in the current language. Falls back to
    /// English, then to the raw key, so a missing entry is visible rather than
    /// crashing or blanking the UI.
    static func string(_ key: String) -> String {
        let lang = Defaults.language
        let value = bundle(for: lang).localizedString(forKey: key, value: missing, table: nil)
        if value != missing { return value }
        if lang != .en {
            let english = bundle(for: .en).localizedString(forKey: key, value: missing, table: nil)
            if english != missing { return english }
        }
        return key
    }
}
