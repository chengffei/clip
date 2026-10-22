import Foundation

enum OCRProviderKind: String, CaseIterable, Codable {
    case apple, baidu, tencent, google, azure, ocrSpace, openAICompatible, ollama

    var displayName: String {
        switch self {
        case .apple: return L10n.ocrProviderApple
        case .baidu: return L10n.ocrProviderBaidu
        case .tencent: return L10n.ocrProviderTencent
        case .google: return "Google Cloud Vision"
        case .azure: return "Azure AI Vision"
        case .ocrSpace: return "OCR.space"
        case .openAICompatible: return L10n.ocrProviderCompatible
        case .ollama: return "Ollama"
        }
    }

    var hasGeometry: Bool { self != .openAICompatible && self != .ollama }
    var needsModel: Bool { self == .openAICompatible || self == .ollama }
    var needsSecret: Bool { self == .baidu || self == .tencent }
    var needsEndpoint: Bool { self == .openAICompatible || self == .ollama || self == .azure }

    var defaultEndpoint: String {
        switch self {
        case .openAICompatible: return "https://api.openai.com/v1/chat/completions"
        case .ollama: return "http://localhost:11434/api/chat"
        default: return ""
        }
    }

    var documentationURL: URL {
        let value: String
        switch self {
        case .apple: value = "https://developer.apple.com/documentation/vision/recognizing-text-in-images"
        case .baidu: value = "https://ai.baidu.com/ai-doc/OCR/Nkibizxlf"
        case .tencent: value = "https://cloud.tencent.com/document/api/866/33526"
        case .google: value = "https://docs.cloud.google.com/vision/docs/ocr"
        case .azure: value = "https://learn.microsoft.com/en-us/azure/ai-services/computer-vision/how-to/call-analyze-image-40"
        case .ocrSpace: value = "https://ocr.space/ocrapi"
        case .openAICompatible: value = "https://developers.openai.com/api/docs/guides/images-vision"
        case .ollama: value = "https://docs.ollama.com/capabilities/vision"
        }
        return URL(string: value)!
    }
}

struct OCRProviderConfig: Codable {
    var apiKey = ""
    var secretKey = ""
    var endpoint = ""
    var model = ""
    var region = "ap-guangzhou"

    func normalized() -> Self {
        func trim(_ value: String) -> String { value.trimmingCharacters(in: .whitespacesAndNewlines) }
        return Self(apiKey: trim(apiKey), secretKey: trim(secretKey), endpoint: trim(endpoint),
                    model: trim(model), region: trim(region))
    }

    func resolvedEndpoint(for kind: OCRProviderKind) -> String {
        endpoint.isEmpty ? kind.defaultEndpoint : endpoint
    }

    func validate(for kind: OCRProviderKind) throws {
        if kind == .apple { return }
        if !kind.needsModel && apiKey.isEmpty { throw OCRProviderError.configuration }
        if kind.needsSecret && secretKey.isEmpty { throw OCRProviderError.configuration }
        if kind.needsModel && model.isEmpty { throw OCRProviderError.configuration }
        if kind == .tencent && region.isEmpty { throw OCRProviderError.configuration }
        if kind.needsEndpoint { _ = try OCRProviderConfig.validatedURL(resolvedEndpoint(for: kind)) }
    }

    /// Permit plain HTTP only for a local model server. Cloud credentials and
    /// screenshots must travel over TLS. Use the full API URL, without guessing paths.
    static func validatedURL(_ endpoint: String) throws -> URL {
        guard let url = URL(string: endpoint), let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.fragment == nil,
              url.scheme == "https" || (url.scheme == "http"
                && ["localhost", "127.0.0.1", "[::1]", "::1"].contains(host.lowercased())) else {
            throw OCRProviderError.endpoint
        }
        return url
    }
}

/// Follows the existing translation-provider persistence convention. Each
/// provider retains its own settings when the selected provider changes.
enum OCRConfigStore {
    static func load(_ kind: OCRProviderKind) -> OCRProviderConfig {
        guard let data = UserDefaults.standard.data(forKey: key(kind)),
              let config = try? JSONDecoder().decode(OCRProviderConfig.self, from: data) else {
            return OCRProviderConfig()
        }
        return config.normalized()
    }

    static func save(_ config: OCRProviderConfig, for kind: OCRProviderKind) {
        if let data = try? JSONEncoder().encode(config.normalized()) {
            UserDefaults.standard.set(data, forKey: key(kind))
        }
    }

    private static func key(_ kind: OCRProviderKind) -> String { "ocr.\(kind.rawValue).config" }
}

struct OCRResult {
    let text: String
    let lines: [RecognizedTextLine]
    let provider: OCRProviderKind

    init(text: String? = nil, lines: [RecognizedTextLine] = [], provider: OCRProviderKind) {
        self.text = (text ?? lines.map(\.text).joined(separator: "\n"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.lines = lines
        self.provider = provider
    }
}

enum OCRProviderError: LocalizedError {
    case configuration, endpoint, image, response, timeout
    case http(Int)
    case service(String)

    var errorDescription: String? {
        switch self {
        case .configuration: return L10n.ocrConfigurationError
        case .endpoint: return L10n.ocrEndpointError
        case .image: return L10n.ocrImageError
        case .response: return L10n.ocrResponseError
        case .timeout: return L10n.ocrTimeoutError
        case .http(let code): return "\(L10n.ocrRequestFailed) HTTP \(code)"
        case .service(let code): return "\(L10n.ocrRequestFailed) \(code)"
        }
    }
}
