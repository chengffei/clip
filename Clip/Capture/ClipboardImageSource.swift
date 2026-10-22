import AppKit
import UniformTypeIdentifiers

/// Pulls an editable image out of the system clipboard for explicit edit and
/// pin shortcuts.
enum ClipboardImageSource {
    /// Returns an image when the clipboard holds one — either raw bitmap data
    /// (a copied screenshot, an image dragged from a browser, etc.) or a
    /// single copied image file. Returns nil when the clipboard has no image.
    static func currentImage() -> NSImage? {
        let pasteboard = NSPasteboard.general

        let imageFileURLs = currentImageFileURLs()

        // A copied image file (e.g. ⌘C on a file in Finder) takes priority.
        // Finder puts the file's *icon* on the clipboard as TIFF data too, so
        // the raw-bitmap path below would decode that generic document icon
        // instead of the real image. Load from the file URL first.
        if imageFileURLs.count == 1,
           let data = try? Data(contentsOf: imageFileURLs[0]) {
            return NSImage.imagePreservingPixelDimensions(from: data)
        }

        if !imageFileURLs.isEmpty {
            return nil
        }

        // Otherwise fall back to raw bitmap data: a copied screenshot or web
        // image. Decode through NSBitmapImageRep so the editor canvas works at
        // the image's true pixel resolution rather than DPI-scaled points.
        for type in bitmapPasteboardTypes {
            if let data = pasteboard.data(forType: type),
               let image = NSImage.imagePreservingPixelDimensions(from: data) {
                return image
            }
        }

        return nil
    }

    /// Empties the clipboard. Used by pin mode so the same source is not
    /// re-pinned.
    static func clear() {
        NSPasteboard.general.clearContents()
    }

    /// Returns all copied image file URLs on the clipboard, preserving the
    /// pasteboard order. This lets multi-image workflows import Finder copies.
    static func currentImageFileURLs() -> [URL] {
        let pasteboard = NSPasteboard.general
        guard let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] else {
            return []
        }
        return urls.filter(isImage)
    }

    private static let bitmapPasteboardTypes: [NSPasteboard.PasteboardType] = [
        .png,
        .tiff,
        NSPasteboard.PasteboardType(UTType.jpeg.identifier),
        NSPasteboard.PasteboardType(UTType.heic.identifier),
        NSPasteboard.PasteboardType("public.heif"),
        NSPasteboard.PasteboardType("org.webmproject.webp"),
    ]

    private static func isImage(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.contentTypeKey])
        guard let type = values?.contentType else { return false }
        return type.conforms(to: .image)
    }
}

enum ClipboardTextSource {
    static func currentText() -> String? {
        guard let text = NSPasteboard.general.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }
        return text
    }
}
