import Foundation

enum ScreenshotImageQuality: String, CaseIterable {
    case original
    case compressed

    static let defaultValue: ScreenshotImageQuality = .original

    var localizedTitle: String {
        switch self {
        case .original: return L10n.screenshotQualityOriginal
        case .compressed: return L10n.screenshotQualityCompressed
        }
    }

    var localizedHint: String {
        switch self {
        case .original: return L10n.screenshotQualityOriginalHint
        case .compressed: return L10n.screenshotQualityCompressedHint
        }
    }

    var fileExtension: String {
        switch self {
        case .original: return "png"
        case .compressed: return "compressed.png"
        }
    }

    var contentType: String {
        "image/png"
    }

    var usesLossyCompression: Bool {
        self == .compressed
    }
}
