import Foundation

protocol DirectTranslationProvider {
    static func translate(
        text: String,
        target: TranslationLanguage,
        config: TranslationConfig
    ) async throws -> String
}
