import AppKit
import CoreImage

enum MosaicStyle: String {
    case pixelate
    case blur
}

struct MosaicRegion {
    let rect: NSRect
    let pixelatedImage: NSImage
}

struct MosaicTool {
    private static let context = CIContext()

    /// Apply the selected obscuring effect to the screenshot region.
    static func createMosaicRegion(
        rect: NSRect,
        imageSize: NSSize,
        baseImage: NSImage,
        blockSize: CGFloat = 12,
        style: MosaicStyle = .pixelate,
        blurRadius: CGFloat = 12
    ) -> MosaicRegion? {
        guard imageSize.width > 0, imageSize.height > 0 else { return nil }
        // Clamp the dragged rect to the image bounds.
        let clamped = rect.intersection(NSRect(origin: .zero, size: imageSize))
        guard clamped.width > 0, clamped.height > 0 else { return nil }

        // Extract the sub-image for this region.
        guard let cgImage = baseImage.cgImagePreservingBacking() else { return nil }

        let scale = CGFloat(cgImage.width) / imageSize.width
        if style == .blur {
            // Core Image uses bottom-left coordinates, matching the canvas.
            // Blur before cropping so the selection edge samples its actual
            // neighbours. Clamp the screenshot edges to avoid transparent halos.
            let ciImage = CIImage(cgImage: cgImage)
            let region = CGRect(
                x: clamped.minX * scale,
                y: clamped.minY * CGFloat(cgImage.height) / imageSize.height,
                width: clamped.width * scale,
                height: clamped.height * CGFloat(cgImage.height) / imageSize.height
            )
            let radius = CGFloat(Defaults.normalizedMosaicBlurRadius(Double(blurRadius)))
            let blurred = ciImage.clampedToExtent().applyingFilter(
                "CIGaussianBlur",
                parameters: [kCIInputRadiusKey: radius * scale]
            ).cropped(to: region)
            guard let outputCG = context.createCGImage(blurred, from: region) else { return nil }
            return MosaicRegion(
                rect: clamped,
                pixelatedImage: NSImage(cgImage: outputCG, size: clamped.size)
            )
        }
        // CGImage cropping uses top-left coordinates, so flip the canvas Y.
        let cgRegion = CGRect(
            x: clamped.origin.x * scale,
            y: (imageSize.height - clamped.origin.y - clamped.height) * scale,
            width: clamped.width * scale,
            height: clamped.height * scale
        )

        guard let croppedCG = cgImage.cropping(to: cgRegion) else { return nil }

        // Apply pixelation using CIFilter.
        let ciImage = CIImage(cgImage: croppedCG)
        let pixelateFilter = CIFilter(name: "CIPixellate")!
        pixelateFilter.setValue(ciImage, forKey: kCIInputImageKey)
        pixelateFilter.setValue(max(blockSize, 4), forKey: kCIInputScaleKey)
        pixelateFilter.setValue(CIVector(x: ciImage.extent.midX, y: ciImage.extent.midY), forKey: kCIInputCenterKey)

        guard let outputCI = pixelateFilter.outputImage else { return nil }

        guard let outputCG = context.createCGImage(outputCI, from: ciImage.extent) else { return nil }

        let pixelatedImage = NSImage(cgImage: outputCG, size: clamped.size)
        return MosaicRegion(rect: clamped, pixelatedImage: pixelatedImage)
    }
}
