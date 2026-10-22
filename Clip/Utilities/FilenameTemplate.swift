import AppKit
import Foundation

enum FilenameTemplate {
    enum OutputKind: String {
        case image
        case recording

        var typeValue: String {
            switch self {
            case .image: return "screenshot"
            case .recording: return "recording"
            }
        }

        var fallbackBase: String {
            switch self {
            case .image: return "capcap"
            case .recording: return "capcap-rec"
            }
        }

        var storedTemplate: String {
            switch self {
            case .image: return Defaults.imageFilenameTemplate
            case .recording: return Defaults.recordingFilenameTemplate
            }
        }
    }

    struct Context {
        var date: Date
        var imageSize: CGSize?
    }

    static func imageFileName(
        for image: NSImage?,
        fileExtension: String = "png",
        imageSize: CGSize? = nil,
        date: Date = Date(),
        consumeCounters: Bool = true
    ) -> String {
        renderFileName(
            kind: .image,
            template: OutputKind.image.storedTemplate,
            fileExtension: fileExtension,
            context: Context(date: date, imageSize: imageSize ?? pixelSize(from: image)),
            consumeCounters: consumeCounters
        )
    }

    static func recordingFileName(
        fileExtension: String,
        date: Date = Date(),
        consumeCounters: Bool = true
    ) -> String {
        renderFileName(
            kind: .recording,
            template: OutputKind.recording.storedTemplate,
            fileExtension: fileExtension,
            context: Context(date: date, imageSize: nil),
            consumeCounters: consumeCounters
        )
    }

    static func previewFileName(
        kind: OutputKind,
        template: String,
        fileExtension: String,
        date: Date = Date(),
        imageSize: CGSize? = CGSize(width: 1440, height: 900)
    ) -> String {
        renderFileName(
            kind: kind,
            template: template,
            fileExtension: fileExtension,
            context: Context(date: date, imageSize: imageSize),
            consumeCounters: false
        )
    }

    private static func renderFileName(
        kind: OutputKind,
        template: String,
        fileExtension: String,
        context: Context,
        consumeCounters: Bool
    ) -> String {
        let rendered = renderBase(
            kind: kind,
            template: template,
            context: context,
            consumeCounters: consumeCounters
        )
        let withoutExtension = stripMatchingExtension(rendered, fileExtension: fileExtension)
        let safeBase = sanitizeBase(withoutExtension, fallback: kind.fallbackBase)
        return "\(safeBase).\(fileExtension)"
    }

    private static func renderBase(
        kind: OutputKind,
        template: String,
        context: Context,
        consumeCounters: Bool
    ) -> String {
        let dayStamp = formatted(context.date, "yyyyMMdd")
        var output = ""
        var index = template.startIndex
        var cachedCounter: Int?
        var cachedDailyCounter: Int?

        while index < template.endIndex {
            guard template[index] == "{" else {
                output.append(template[index])
                index = template.index(after: index)
                continue
            }

            let afterOpen = template.index(after: index)
            guard let close = template[afterOpen...].firstIndex(of: "}") else {
                output.append(template[index])
                index = afterOpen
                continue
            }

            let token = String(template[afterOpen..<close])
            output += value(
                for: token,
                kind: kind,
                context: context,
                dayStamp: dayStamp,
                consumeCounters: consumeCounters,
                cachedCounter: &cachedCounter,
                cachedDailyCounter: &cachedDailyCounter
            )
            index = template.index(after: close)
        }

        return output
    }

    private static func value(
        for rawToken: String,
        kind: OutputKind,
        context: Context,
        dayStamp: String,
        consumeCounters: Bool,
        cachedCounter: inout Int?,
        cachedDailyCounter: inout Int?
    ) -> String {
        let pieces = rawToken.split(separator: ":", maxSplits: 1).map(String.init)
        let token = pieces.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let width = pieces.dropFirst().first.flatMap { Int($0) }.map { min(max($0, 1), 8) } ?? 0

        switch token {
        case "date": return formatted(context.date, "yyMMdd")
        case "time": return formatted(context.date, "HHmmss")
        case "yyyy": return formatted(context.date, "yyyy")
        case "yy": return formatted(context.date, "yy")
        case "MM": return formatted(context.date, "MM")
        case "dd": return formatted(context.date, "dd")
        case "HH": return formatted(context.date, "HH")
        case "mm": return formatted(context.date, "mm")
        case "ss": return formatted(context.date, "ss")
        case "counter":
            if cachedCounter == nil {
                cachedCounter = Defaults.filenameSequenceValue(
                    scope: kind.rawValue,
                    dayStamp: nil,
                    consume: consumeCounters
                )
            }
            return padded(cachedCounter ?? 1, width: width)
        case "daily":
            if cachedDailyCounter == nil {
                cachedDailyCounter = Defaults.filenameSequenceValue(
                    scope: kind.rawValue,
                    dayStamp: dayStamp,
                    consume: consumeCounters
                )
            }
            return padded(cachedDailyCounter ?? 1, width: width)
        case "rand":
            return randomToken(length: width == 0 ? 4 : width)
        case "width":
            guard let width = context.imageSize?.width else { return "" }
            return "\(Int(width.rounded()))"
        case "height":
            guard let height = context.imageSize?.height else { return "" }
            return "\(Int(height.rounded()))"
        case "type":
            return kind.typeValue
        default:
            return token
        }
    }

    private static func pixelSize(from image: NSImage?) -> CGSize? {
        guard let cgImage = image?.cgImagePreservingBacking() else { return nil }
        return CGSize(width: cgImage.width, height: cgImage.height)
    }

    private static func formatted(_ date: Date, _ format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    private static func padded(_ value: Int, width: Int) -> String {
        guard width > 0 else { return "\(value)" }
        let text = "\(value)"
        guard text.count < width else { return text }
        return String(repeating: "0", count: width - text.count) + text
    }

    private static func randomToken(length: Int) -> String {
        let targetLength = min(max(length, 1), 16)
        var text = ""
        while text.count < targetLength {
            text += UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        }
        return String(text.prefix(targetLength))
    }

    private static func stripMatchingExtension(_ base: String, fileExtension: String) -> String {
        let lower = base.lowercased()
        let suffixes: [String]
        if fileExtension.lowercased() == "compressed.png" {
            suffixes = [".compressed.png", ".png", ".jpg", ".jpeg"]
        } else {
            suffixes = [".\(fileExtension.lowercased())"]
        }

        for suffix in suffixes where lower.hasSuffix(suffix) {
            guard let end = base.index(base.endIndex, offsetBy: -suffix.count, limitedBy: base.startIndex) else {
                continue
            }
            return String(base[..<end])
        }
        return base
    }

    private static func sanitizeBase(_ raw: String, fallback: String) -> String {
        let forbidden = Set("/\\:?%*|\"<>#&{}[]".unicodeScalars)
        var output = ""
        var previousWasDash = false

        func appendDash() {
            guard !previousWasDash else { return }
            output.append("-")
            previousWasDash = true
        }

        for scalar in raw.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                appendDash()
            } else if CharacterSet.controlCharacters.contains(scalar) || forbidden.contains(scalar) {
                appendDash()
            } else {
                output.unicodeScalars.append(scalar)
                previousWasDash = false
            }
        }

        let trimmed = output.trimmingCharacters(in: CharacterSet(charactersIn: ".-_ "))
        guard !trimmed.isEmpty else { return fallback }
        return String(trimmed.prefix(120))
    }
}
