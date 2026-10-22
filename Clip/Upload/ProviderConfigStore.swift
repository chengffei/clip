import Foundation

/// Persists provider configs in UserDefaults under one JSON-encoded key per provider.
enum ProviderConfigStore {
    private static func configKey(for kind: UploadProviderKind) -> String {
        "uploader.\(kind.rawValue).config"
    }

    private static func enabledKey(for kind: UploadProviderKind) -> String {
        "uploader.\(kind.rawValue).enabled"
    }

    static func load(kind: UploadProviderKind) -> ProviderConfig? {
        guard let data = UserDefaults.standard.data(forKey: configKey(for: kind)),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            return nil
        }
        return ProviderConfig(kind: kind, fields: dict)
    }

    static func save(_ config: ProviderConfig) {
        if let data = try? JSONEncoder().encode(config.fields) {
            UserDefaults.standard.set(data, forKey: configKey(for: config.kind))
        }
        NotificationCenter.default.post(name: .uploadProvidersDidChange, object: nil)
    }

    static func clear(kind: UploadProviderKind) {
        UserDefaults.standard.removeObject(forKey: configKey(for: kind))
        NotificationCenter.default.post(name: .uploadProvidersDidChange, object: nil)
    }

    /// User toggle controlling whether the provider participates in the upload pipeline.
    /// Defaults to true when a valid config already exists (preserves prior behavior),
    /// otherwise false.
    static func isEnabled(kind: UploadProviderKind) -> Bool {
        let key = enabledKey(for: kind)
        if UserDefaults.standard.object(forKey: key) == nil {
            guard let cfg = load(kind: kind) else { return false }
            return Uploaders.provider(for: kind).validate(cfg) == nil
        }
        return UserDefaults.standard.bool(forKey: key)
    }

    static func setEnabled(_ enabled: Bool, kind: UploadProviderKind) {
        UserDefaults.standard.set(enabled, forKey: enabledKey(for: kind))
        NotificationCenter.default.post(name: .uploadProvidersDidChange, object: nil)
    }

    /// True when the provider is enabled AND its saved config passes validate().
    static func isUsable(kind: UploadProviderKind) -> Bool {
        guard isEnabled(kind: kind), let cfg = load(kind: kind) else { return false }
        return Uploaders.provider(for: kind).validate(cfg) == nil
    }

    /// Kinds with a usable saved config.
    static func usableKinds() -> [UploadProviderKind] {
        UploadProviderKind.allCases.filter { isUsable(kind: $0) }
    }
}

extension Notification.Name {
    static let uploadProvidersDidChange = Notification.Name("capcap.uploadProvidersDidChange")
}

extension Defaults {
    /// Persisted by raw value. Falls back to the first usable provider when no
    /// explicit default is set (or the stored one became unusable), so a single
    /// configured provider works without the user having to click "Set Default".
    static var defaultUploadProviderKind: UploadProviderKind? {
        get {
            if let raw = UserDefaults.standard.string(forKey: "uploader.defaultKind"),
               let kind = UploadProviderKind(rawValue: raw),
               ProviderConfigStore.isUsable(kind: kind) {
                return kind
            }
            return ProviderConfigStore.usableKinds().first
        }
        set {
            if let v = newValue {
                UserDefaults.standard.set(v.rawValue, forKey: "uploader.defaultKind")
            } else {
                UserDefaults.standard.removeObject(forKey: "uploader.defaultKind")
            }
            NotificationCenter.default.post(name: .uploadProvidersDidChange, object: nil)
        }
    }

    static var hasUsableUploadProvider: Bool {
        defaultUploadProviderKind != nil
    }

    /// When enabled, a successful upload copies a Markdown image tag
    /// (`![](url)`) to the clipboard instead of a bare URL. Defaults to off.
    static var copyUploadAsMarkdown: Bool {
        get { UserDefaults.standard.bool(forKey: "uploader.copyAsMarkdown") }
        set { UserDefaults.standard.set(newValue, forKey: "uploader.copyAsMarkdown") }
    }
}
