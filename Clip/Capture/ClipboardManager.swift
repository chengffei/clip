import AppKit

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

    static func copyToClipboard(text: String) {
        writeTextToClipboard(text)
    }

    static func copyColorToClipboard(hex: String) {
        guard let normalizedHex = ClipboardColorParser.normalizedHex(from: hex) else {
            writeTextToClipboard(hex)
            return
        }
        writeTextToClipboard(normalizedHex)
    }

    private static func writeTextToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

