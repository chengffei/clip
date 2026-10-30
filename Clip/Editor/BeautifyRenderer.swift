import AppKit
import CoreGraphics
import ImageIO

enum BeautifyRenderer {
    // MARK: - Layout constants

    static let innerCornerRadius: CGFloat = 12
    // Same range as window capture, with an independently saved size.
    static let shadowSizeMin = CGFloat(Defaults.windowShadowSizeMin)
    static let shadowSizeMax = CGFloat(Defaults.windowShadowSizeMax)
    static let shadowSizeDefault: CGFloat = 24

    static func normalizedShadowSize(_ size: CGFloat) -> CGFloat {
        guard size.isFinite else { return shadowSizeDefault }
        return min(max(size, shadowSizeMin), shadowSizeMax)
    }

    /// Match the per-edge margins of a window screenshot at the same size.
    static func padding(forShadowSize size: CGFloat, shadowEnabled: Bool) -> NSEdgeInsets {
        guard shadowEnabled else { return NSEdgeInsetsZero }
        return WindowEffects.shadowPadding(forSize: normalizedShadowSize(size))
    }

    // MARK: - Wallpaper

    /// Longest-edge pixel cap for the cached wallpaper bitmap. The raw desktop
    /// image is often a multi-frame "dynamic" HEIC well over 100 MB; that only
    /// ever fills the thin padding band, so a 2560 px copy is plenty.
    private static let wallpaperMaxEdge: CGFloat = 2560

    /// Decoded + downscaled wallpaper bitmaps, keyed by source file path.
    private static var wallpaperCache: [String: NSImage] = [:]
    private static var wallpaperLoadCallbacks: [String: [(NSImage?) -> Void]] = [:]
    private static let wallpaperCacheLock = NSLock()
    private static let wallpaperDecodeQueue = DispatchQueue(
        label: "clip.beautify.wallpaper.decode",
        qos: .userInitiated
    )


    /// Asynchronously loads the desktop wallpaper image for the given screen.
    /// Completion is always delivered on the main queue.
    static func loadWallpaperImage(for screen: NSScreen, completion: @escaping (NSImage?) -> Void) {
        guard let url = NSWorkspace.shared.desktopImageURL(for: screen) else {
            DispatchQueue.main.async {
                completion(nil)
            }
            return
        }

        if let cached = cachedWallpaper(url: url) {
            DispatchQueue.main.async {
                completion(cached)
            }
            return
        }

        let key = url.path
        wallpaperCacheLock.lock()
        if var callbacks = wallpaperLoadCallbacks[key] {
            callbacks.append(completion)
            wallpaperLoadCallbacks[key] = callbacks
            wallpaperCacheLock.unlock()
            return
        }
        wallpaperLoadCallbacks[key] = [completion]
        wallpaperCacheLock.unlock()

        wallpaperDecodeQueue.async {
            let image = autoreleasepool {
                downscaledWallpaper(url: url)
            }
            if let image {
                storeWallpaper(image, url: url)
            }

            wallpaperCacheLock.lock()
            let callbacks = wallpaperLoadCallbacks.removeValue(forKey: key) ?? []
            wallpaperCacheLock.unlock()

            DispatchQueue.main.async {
                callbacks.forEach { $0(image) }
            }
        }
    }


    private static func cachedWallpaper(url: URL) -> NSImage? {
        let key = url.path
        wallpaperCacheLock.lock()
        let cached = wallpaperCache[key]
        wallpaperCacheLock.unlock()
        return cached
    }

    private static func storeWallpaper(_ image: NSImage, url: URL) {
        wallpaperCacheLock.lock()
        wallpaperCache[url.path] = image
        wallpaperCacheLock.unlock()
    }

    /// Decodes only the primary frame of `url`, downscaled so the longest edge
    /// is at most `wallpaperMaxEdge`. `CGImageSourceCreateThumbnailAtIndex`
    /// performs the scaling inside ImageIO, so a 100 MB+ dynamic wallpaper is
    /// never fully decoded into memory.
    private static func downscaledWallpaper(url: URL) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return NSImage(contentsOf: url)
        }
        let index = CGImageSourceGetPrimaryImageIndex(source)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: wallpaperMaxEdge,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary) else {
            return NSImage(contentsOf: url)
        }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    // MARK: - Drawing primitives

    /// Quartz path clips have hard pixel edges. Rasterize a filled path instead
    /// so the clip carries fractional coverage at the destination's pixel scale.
    /// The live canvas retains this cache across annotation redraws.
    final class CornerMask {
        private var cachedSize: CGSize = .zero
        private var cachedRadius: CGFloat = -1
        private var cachedPixelWidth = 0
        private var cachedPixelHeight = 0
        private var cachedImage: CGImage?

        func clip(_ context: CGContext, to rect: CGRect, radius: CGFloat) {
            guard rect.width > 0, rect.height > 0 else { return }
            let transform = context.ctm
            let pixelWidth = max(1, Int(ceil(rect.width * hypot(transform.a, transform.b))))
            let pixelHeight = max(1, Int(ceil(rect.height * hypot(transform.c, transform.d))))
            let radius = max(0, min(radius, min(rect.width, rect.height) / 2))

            if cachedImage == nil || cachedSize != rect.size || cachedRadius != radius
                || cachedPixelWidth != pixelWidth || cachedPixelHeight != pixelHeight {
                guard let maskContext = CGContext(
                    data: nil,
                    width: pixelWidth,
                    height: pixelHeight,
                    bitsPerComponent: 8,
                    bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceGray(),
                    bitmapInfo: CGImageAlphaInfo.none.rawValue
                ) else { return }

                maskContext.setFillColor(gray: 0, alpha: 1)
                maskContext.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
                maskContext.scaleBy(
                    x: CGFloat(pixelWidth) / rect.width,
                    y: CGFloat(pixelHeight) / rect.height
                )
                maskContext.setAllowsAntialiasing(true)
                maskContext.setShouldAntialias(true)
                maskContext.setFillColor(gray: 1, alpha: 1)
                maskContext.addPath(CGPath(
                    roundedRect: CGRect(origin: .zero, size: rect.size),
                    cornerWidth: radius,
                    cornerHeight: radius,
                    transform: nil
                ))
                maskContext.fillPath()
                guard let image = maskContext.makeImage() else { return }
                cachedImage = image
                cachedSize = rect.size
                cachedRadius = radius
                cachedPixelWidth = pixelWidth
                cachedPixelHeight = pixelHeight
            }

            if let cachedImage {
                context.clip(to: rect, mask: cachedImage)
            }
        }
    }

    /// Draws a linear gradient across `outerRect` using the preset colors and angle.
    /// Wallpaper and transparent presets leave the area empty (caller draws
    /// wallpaper / checkerboard separately for preview; export clears alpha).
    static func drawBackground(in outerRect: CGRect, preset: BeautifyPreset) {
        if preset.isWallpaper || preset.isTransparent { return }
        guard let gradient = NSGradient(starting: preset.startColor, ending: preset.endColor) else {
            preset.startColor.setFill()
            outerRect.fill()
            return
        }
        gradient.draw(in: outerRect, angle: preset.angleDegrees)
    }

    /// Checkerboard used only in the editor preview so transparent padding
    /// and rounded corners stay visible. Never baked into exported images.
    static func drawCheckerboard(in rect: CGRect, square: CGFloat = 14) {
        guard square > 0, rect.width > 0, rect.height > 0 else { return }
        var y = rect.minY
        var row = 0
        while y < rect.maxY {
            var x = rect.minX
            var column = 0
            while x < rect.maxX {
                let isLight = (row + column).isMultiple(of: 2)
                (isLight
                    ? NSColor(calibratedWhite: 0.88, alpha: 1)
                    : NSColor(calibratedWhite: 0.72, alpha: 1)
                ).setFill()
                NSRect(
                    x: x,
                    y: y,
                    width: min(square, rect.maxX - x),
                    height: min(square, rect.maxY - y)
                ).fill()
                x += square
                column += 1
            }
            y += square
            row += 1
        }
    }

    /// Draws a wallpaper image as background, aspect-fill centered in `outerRect`.
    static func drawWallpaperBackground(in outerRect: CGRect, wallpaper: NSImage) {
        let wpSize = wallpaper.size
        guard wpSize.width > 0, wpSize.height > 0 else { return }
        let scaleX = outerRect.width / wpSize.width
        let scaleY = outerRect.height / wpSize.height
        let scale = max(scaleX, scaleY)
        let drawSize = CGSize(width: wpSize.width * scale, height: wpSize.height * scale)
        let drawRect = CGRect(
            x: outerRect.origin.x + (outerRect.width - drawSize.width) / 2,
            y: outerRect.origin.y + (outerRect.height - drawSize.height) / 2,
            width: drawSize.width,
            height: drawSize.height
        )
        wallpaper.draw(
            in: drawRect,
            from: .zero,
            operation: .sourceOver,
            fraction: 1.0,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high.rawValue]
        )
    }

    /// Apply the same corner mask to both the displayed image and its shadow
    /// source. Clicked-window images already contain their real alpha mask.
    static func shadowSource(
        from image: CGImage,
        imageSize: CGSize,
        cornerRadius: CGFloat?
    ) -> CGImage? {
        guard let cornerRadius else { return image }
        guard imageSize.width > 0, imageSize.height > 0,
              let context = CGContext(
                data: nil, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        context.scaleBy(
            x: CGFloat(image.width) / imageSize.width,
            y: CGFloat(image.height) / imageSize.height
        )
        let rect = CGRect(origin: .zero, size: imageSize)
        CornerMask().clip(context, to: rect, radius: cornerRadius)
        context.interpolationQuality = .none
        context.draw(image, in: rect)
        return context.makeImage()
    }

    // MARK: - Full composite

    /// Automatically fits the projection unless an explicit margin is supplied
    /// by the pixel-based agent API, which owns its output dimensions and offsets.
    static func render(
        innerImage: NSImage,
        preset: BeautifyPreset,
        padding: CGFloat? = nil,
        wallpaperImage: NSImage? = nil,
        shadowEnabled: Bool = true,
        shadowSize: CGFloat = shadowSizeDefault,
        innerClipRadius: CGFloat? = BeautifyRenderer.innerCornerRadius
    ) -> NSImage {
        let innerSize = innerImage.size
        guard innerSize.width > 0, innerSize.height > 0 else { return innerImage }

        guard let backing = innerImage.cgImagePreservingBacking(),
              let source = shadowSource(
                from: backing, imageSize: innerSize, cornerRadius: innerClipRadius
              ) else { return innerImage }

        let margins: NSEdgeInsets
        if let padding {
            // The pixel-based agent API explicitly owns its symmetric margin.
            let p = max(0, padding)
            margins = NSEdgeInsets(top: p, left: p, bottom: p, right: p)
        } else {
            margins = self.padding(forShadowSize: shadowSize, shadowEnabled: shadowEnabled)
        }

        // Sliders retain fractional points even when their labels show integers.
        // Align each margin to backing pixels and keep the screenshot's exact
        // pixel dimensions; rounding only the outer size resamples its contents.
        let scaleX = CGFloat(source.width) / innerSize.width
        let scaleY = CGFloat(source.height) / innerSize.height
        let leftPixels = Int((margins.left * scaleX).rounded())
        let bottomPixels = Int((margins.bottom * scaleY).rounded())
        let pixelsWide = source.width + (padding != nil
            ? 2 * leftPixels
            : Int(((margins.left + margins.right) * scaleX).rounded()))
        let pixelsHigh = source.height + (padding != nil
            ? 2 * bottomPixels
            : Int(((margins.top + margins.bottom) * scaleY).rounded()))
        let outer = CGSize(width: CGFloat(pixelsWide) / scaleX, height: CGFloat(pixelsHigh) / scaleY)
        let outerRect = CGRect(origin: .zero, size: outer)
        let inner = CGRect(
            x: CGFloat(leftPixels) / scaleX,
            y: CGFloat(bottomPixels) / scaleY,
            width: innerSize.width,
            height: innerSize.height
        )

        guard let cg = CGContext(
            data: nil,
            width: pixelsWide,
            height: pixelsHigh,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return innerImage }
        cg.scaleBy(x: scaleX, y: scaleY)
        let ctx = NSGraphicsContext(cgContext: cg, flipped: false)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        ctx.imageInterpolation = .high

        // 1. Background — transparent presets keep pure alpha (no desktop,
        // no wallpaper, no gradient). Checkerboard is preview-only.
        if preset.isTransparent {
            cg.clear(outerRect)
        } else if preset.isWallpaper, let wp = wallpaperImage {
            drawWallpaperBackground(in: outerRect, wallpaper: wp)
        } else {
            drawBackground(in: outerRect, preset: preset)
        }

        // 2. Cast from the same alpha as the image, using the window renderer.
        if shadowEnabled {
            WindowEffects.drawShadow(
                image: source,
                sourceRect: inner,
                size: normalizedShadowSize(shadowSize),
                baseScale: CGSize(width: scaleX, height: scaleY),
                context: cg
            )
        }

        // 3. The source already carries the final corner/alpha mask.
        cg.saveGState()
        // Draw the original backing directly, without AppKit representation
        // selection or interpolation of text and single-pixel lines.
        cg.interpolationQuality = .none
        cg.draw(source, in: inner)
        cg.restoreGState()

        NSGraphicsContext.restoreGraphicsState()

        guard let rendered = cg.makeImage() else { return innerImage }
        let rep = NSBitmapImageRep(cgImage: rendered)
        rep.size = outer
        let image = NSImage(size: outer)
        image.addRepresentation(rep)
        return image
    }
}
