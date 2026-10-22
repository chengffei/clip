import AppKit
import ImageIO
import UniformTypeIdentifiers

extension NSImage {
    static func imagePreservingPixelDimensions(from data: Data) -> NSImage? {
        if let rep = NSBitmapImageRep(data: data) {
            return imagePreservingPixelDimensions(from: rep)
        }

        guard let source = NSImage(data: data),
              let cgImage = source.cgImagePreservingBacking()
        else {
            return nil
        }

        let rep = NSBitmapImageRep(cgImage: cgImage)
        return imagePreservingPixelDimensions(from: rep)
    }

    private static func imagePreservingPixelDimensions(from rep: NSBitmapImageRep) -> NSImage? {
        let pixelSize = NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        guard pixelSize.width > 0, pixelSize.height > 0 else { return nil }
        rep.size = pixelSize
        let image = NSImage(size: pixelSize)
        image.addRepresentation(rep)
        return image
    }

    private var highestResolutionBitmapRep: NSBitmapImageRep? {
        representations
            .compactMap { $0 as? NSBitmapImageRep }
            .filter { $0.pixelsWide > 0 && $0.pixelsHigh > 0 }
            .max { lhs, rhs in
                (lhs.pixelsWide * lhs.pixelsHigh) < (rhs.pixelsWide * rhs.pixelsHigh)
            }
    }

    func cgImagePreservingBacking() -> CGImage? {
        if let cgImage = highestResolutionBitmapRep?.cgImage {
            return cgImage
        }

        var proposedRect = CGRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)
    }

    func bitmapImageRepPreservingBacking() -> NSBitmapImageRep? {
        guard let cgImage = cgImagePreservingBacking() else { return nil }

        let rep = NSBitmapImageRep(cgImage: cgImage)
        rep.size = size
        return rep
    }

    func pngDataPreservingBacking() -> Data? {
        guard let cgImage = cgImagePreservingBacking() else { return nil }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }

        var properties: [CFString: Any] = [:]
        if size.width > 0, size.height > 0 {
            properties[kCGImagePropertyDPIWidth] = Double(cgImage.width) * 72.0 / Double(size.width)
            properties[kCGImagePropertyDPIHeight] = Double(cgImage.height) * 72.0 / Double(size.height)
        }

        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    func tiffDataPreservingBacking() -> Data? {
        bitmapImageRepPreservingBacking()?.tiffRepresentation
    }
}
