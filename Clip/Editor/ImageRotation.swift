import AppKit

/// Quarter turns in the document's unflipped, bottom-left coordinate system.
/// The source image and annotations stay in this coordinate system while the
/// view hierarchy handles conversion of pointer events into document points.
enum ImageRotation: Int {
    case none, left, upsideDown, right

    var degrees: CGFloat { CGFloat(rawValue) * 90 }

    func turned(clockwise: Bool) -> ImageRotation {
        ImageRotation(rawValue: (rawValue + (clockwise ? 3 : 1)) % 4)!
    }

    func orientedSize(_ size: NSSize) -> NSSize {
        rawValue.isMultiple(of: 2) ? size : NSSize(width: size.height, height: size.width)
    }

    func transform(for size: NSSize) -> CGAffineTransform {
        switch self {
        case .none: return .identity
        case .left: return CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: size.height, ty: 0)
        case .upsideDown: return CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: size.width, ty: size.height)
        case .right: return CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: size.width)
        }
    }

    func documentDelta(fromDisplay delta: NSPoint) -> NSPoint {
        let inverse = transform(for: .zero).inverted()
        return delta.applying(inverse)
    }

    /// Rasterization happens only at an output boundary, at the source pixel
    /// dimensions. Editing never replaces the independent annotation layers.
    func render(_ image: NSImage) -> NSImage? {
        guard self != .none else { return image }
        guard let source = image.cgImagePreservingBacking() else { return nil }
        let sourcePixelSize = NSSize(width: source.width, height: source.height)
        let pixelSize = orientedSize(sourcePixelSize)
        let outputSize = orientedSize(image.size)
        guard let context = CGContext(
            data: nil,
            width: Int(pixelSize.width), height: Int(pixelSize.height),
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // A bitmap context uses pixels, not NSImage's logical points. Rotate
        // the full backing image so Retina output cannot acquire empty margins.
        context.interpolationQuality = .none
        context.concatenate(transform(for: sourcePixelSize))
        context.draw(source, in: NSRect(origin: .zero, size: sourcePixelSize))
        guard let rotatedImage = context.makeImage() else { return nil }
        let bitmap = NSBitmapImageRep(cgImage: rotatedImage)
        bitmap.size = outputSize
        let result = NSImage(size: outputSize)
        result.addRepresentation(bitmap)
        return result
    }
}
