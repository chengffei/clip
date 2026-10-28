import AppKit

private let skipClipboardHistoryPasteboardType = NSPasteboard.PasteboardType(
    "cn.skyrin.capcap.skip-clipboard-text-history"
)

enum ClipboardColorParser {
    static func normalizedHex(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("#") else { return nil }

        let digits = trimmed.dropFirst()
        guard digits.count == 6, UInt32(digits, radix: 16) != nil else { return nil }
        return "#" + digits.uppercased()
    }
}

struct ClipboardManager {
    static func copyToClipboard(
        image: NSImage,
        pasteboard: NSPasteboard = .general
    ) {
        pasteboard.clearContents()

        if let pngData = image.pngDataPreservingBacking() {
            pasteboard.setData(pngData, forType: .png)
        }

        if let tiffData = image.tiffDataPreservingBacking() {
            pasteboard.setData(tiffData, forType: .tiff)
        }
    }

    static func copyToClipboard(imageOutput: EncodedClipboardImageOutput) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(imageOutput.primary.data, forType: imageOutput.primary.pasteboardType)
        if let tiffData = imageOutput.tiffData {
            pasteboard.setData(tiffData, forType: .tiff)
        }
    }

    static func copyToClipboard(text: String, skipHistory: Bool = false) {
        writeTextToClipboard(text, skipHistory: skipHistory)
    }

    static func copyColorToClipboard(hex: String) {
        guard let normalizedHex = ClipboardColorParser.normalizedHex(from: hex) else {
            writeTextToClipboard(hex)
            return
        }
        writeTextToClipboard(normalizedHex, skipHistory: true)
    }



    private static func writeTextToClipboard(_ text: String, skipHistory: Bool = false) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        if skipHistory {
            pasteboard.setString("1", forType: skipClipboardHistoryPasteboardType)
        }
    }
}

