import Foundation
import NaturalLanguage

/// Resolves the actual translation target before a provider request is built.
/// This keeps direction selection deterministic across both chat models and
/// direct translation APIs instead of asking the provider to infer a fallback.
enum TranslationDirectionResolver {
    static func target(
        for text: String,
        preferredTarget: TranslationLanguage
    ) -> TranslationLanguage {
        guard detectedLanguage(in: text) == preferredTarget else {
            return preferredTarget
        }

        // English is the normal fallback for matching source/target text. When
        // English itself is selected, use Chinese so Chinese and English remain
        // bidirectional in every app language.
        return preferredTarget == .english ? .chinese : .english
    }

    static func detectedLanguage(in text: String) -> TranslationLanguage? {
        let sample = String(
            text
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(1_000)
        )
        guard !sample.isEmpty else { return nil }

        let profile = ScriptProfile(text: sample)

        // Kana and Hangul are stronger signals than the shared CJK ideographs.
        if profile.kanaCount > 0 { return .japanese }
        if profile.hangulCount > 0 { return .korean }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)
        let hypothesis = recognizer.languageHypotheses(withMaximum: 1)
            .max(by: { $0.value < $1.value })
        let recognizedLanguage = hypothesis.flatMap {
            translationLanguage(for: $0.key.rawValue)
        }
        let confidence = hypothesis?.value ?? 0

        if recognizedLanguage == .chinese {
            return .chinese
        }
        if recognizedLanguage == .japanese,
           profile.hanCount > 0,
           confidence >= 0.40 {
            return .japanese
        }

        // NaturalLanguage can classify Chinese sentences containing API names
        // and identifiers as English. Multiple Han runs or a meaningful Han
        // share are a more reliable signal for this common technical-text case.
        if profile.isLikelyMixedChinese {
            return .chinese
        }

        if confidence >= 0.45, let recognizedLanguage {
            return recognizedLanguage
        }

        if let scriptLanguage = profile.dominantNonLatinLanguage {
            return scriptLanguage
        }

        // Short English words such as "Hello" often receive a low confidence
        // score even when English is still the recognizer's leading hypothesis.
        if recognizedLanguage == .english, profile.latinCount >= 2 {
            return .english
        }

        // A remaining Han-only sample is most likely Chinese. Confident
        // Japanese Han-only samples have already been handled above.
        if profile.hanCount > 0, profile.latinCount == 0 {
            return .chinese
        }

        return nil
    }

    private static func translationLanguage(for identifier: String) -> TranslationLanguage? {
        let normalized = identifier.lowercased()
        if normalized.hasPrefix("zh") { return .chinese }
        switch normalized {
        case "en": return .english
        case "vi": return .vietnamese
        case "hi": return .hindi
        case "es": return .spanish
        case "fr": return .french
        case "ar": return .arabic
        case "bn": return .bengali
        case "pt": return .portuguese
        case "ru": return .russian
        case "ur": return .urdu
        case "id": return .indonesian
        case "de": return .german
        case "ja": return .japanese
        case "ko": return .korean
        case "tr": return .turkish
        default: return nil
        }
    }
}

private struct ScriptProfile {
    var letterCount = 0
    var latinCount = 0
    var hanCount = 0
    var hanRunCount = 0
    var kanaCount = 0
    var hangulCount = 0
    var nonLatinCounts: [TranslationLanguage: Int] = [:]

    init(text: String) {
        var wasHan = false

        for scalar in text.unicodeScalars {
            let isHan = scalar.isInRange(0x3400...0x4DBF)
                || scalar.isInRange(0x4E00...0x9FFF)
                || scalar.isInRange(0xF900...0xFAFF)

            if isHan {
                hanCount += 1
                if !wasHan { hanRunCount += 1 }
            }
            wasHan = isHan

            guard CharacterSet.letters.contains(scalar) else { continue }
            letterCount += 1

            if scalar.isInRange(0x0041...0x005A)
                || scalar.isInRange(0x0061...0x007A)
                || scalar.isInRange(0x00C0...0x024F) {
                latinCount += 1
            } else if scalar.isInRange(0x3040...0x30FF)
                || scalar.isInRange(0x31F0...0x31FF) {
                kanaCount += 1
            } else if scalar.isInRange(0xAC00...0xD7AF)
                || scalar.isInRange(0x1100...0x11FF) {
                hangulCount += 1
            } else if scalar.isInRange(0x0400...0x04FF) {
                nonLatinCounts[.russian, default: 0] += 1
            } else if scalar.isInRange(0x0600...0x06FF) {
                nonLatinCounts[.arabic, default: 0] += 1
            } else if scalar.isInRange(0x0900...0x097F) {
                nonLatinCounts[.hindi, default: 0] += 1
            } else if scalar.isInRange(0x0980...0x09FF) {
                nonLatinCounts[.bengali, default: 0] += 1
            }
        }
    }

    var isLikelyMixedChinese: Bool {
        guard hanCount >= 2, kanaCount == 0, hangulCount == 0 else {
            return false
        }
        guard latinCount > 0 else { return true }

        let relevantLetterCount = hanCount + latinCount
        let hanShare = Double(hanCount) / Double(relevantLetterCount)
        return hanRunCount >= 2 || hanShare >= 0.25
    }

    var dominantNonLatinLanguage: TranslationLanguage? {
        guard let dominant = nonLatinCounts.max(by: { $0.value < $1.value }),
              dominant.value >= 2,
              letterCount > 0,
              Double(dominant.value) / Double(letterCount) >= 0.30 else {
            return nil
        }
        return dominant.key
    }
}

private extension UnicodeScalar {
    func isInRange(_ range: ClosedRange<UInt32>) -> Bool {
        range.contains(value)
    }
}
