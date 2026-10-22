import AppKit
import QuartzCore

/// Post-processing for window captures: clip the four corners to the rounded
/// shape of a real macOS window, and add a soft system-style drop shadow.
/// Applied only to single-window screenshots, never to free-drag regions.
enum WindowEffects {
    /// Fallback corner radius when a real WindowServer alpha mask is not
    /// available. Normal clicked-window captures use the system-provided mask
    /// instead, because macOS varies the actual corner shape by OS/window style.
    static let cornerRadiusPoints: CGFloat = 16

    private struct ShadowLayer {
        let blur: CGFloat
        let opacity: CGFloat
        let offset: CGSize
    }

    private struct AlphaMaskAnalysis {
        let mask: CGImage
        let visibleBounds: CGRect?
    }

    /// Pixels-per-point of the image's backing bitmap (2 on Retina displays).
    private static func scale(of image: NSImage) -> CGFloat {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return 2
        }
        return CGFloat(cg.width) / max(image.size.width, 1)
    }

    /// Mask the four corners of a window screenshot to transparent. This is a
    /// fallback for cases where a clicked-window capture could not provide the
    /// real WindowServer alpha mask.
    static func roundedCorners(_ image: NSImage, radiusPoints: CGFloat = cornerRadiusPoints) -> NSImage {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return image
        }
        let pw = cg.width
        let ph = cg.height
        guard pw > 0, ph > 0 else { return image }

        guard let mask = continuousCornerMask(
            pixelWidth: pw,
            pixelHeight: ph,
            pointSize: image.size,
            radiusPoints: radiusPoints
        ) else {
            return image
        }

        return applyMask(mask, to: image)
    }

    /// Clip the supplied context to the alpha silhouette of `maskImage`.
    /// The clip is scaled into `rect`, so callers can use an image whose pixel
    /// dimensions differ from the current CGContext backing store.
    @discardableResult
    static func clip(_ context: CGContext, toAlphaOf maskImage: NSImage, in rect: CGRect) -> Bool {
        guard let maskCG = maskImage.cgImagePreservingBacking(),
              let alphaMask = alphaMaskAnalysis(
                from: maskCG,
                width: maskCG.width,
                height: maskCG.height
              )?.mask
        else {
            return false
        }

        context.clip(to: rect, mask: alphaMask)
        return true
    }

    /// Preserve the visible pixels from `image` while borrowing the real
    /// WindowServer alpha silhouette from `maskImage`.
    static func applyingAlphaMask(from maskImage: NSImage, to image: NSImage) -> NSImage? {
        guard let maskCG = maskImage.cgImagePreservingBacking(),
              hasAlpha(maskCG),
              let maskAnalysis = alphaMaskAnalysis(
                from: maskCG,
                width: maskCG.width,
                height: maskCG.height
              ),
              isReliableWindowAlphaMask(maskAnalysis),
              let cg = image.cgImagePreservingBacking()
        else {
            return nil
        }

        let pw = cg.width
        let ph = cg.height
        guard pw > 0, ph > 0 else { return image }

        // Keep the screenshot's own color space (often Display P3) so applying
        // the WindowServer alpha silhouette does not shift the captured pixels.
        let colorSpace: CGColorSpace = {
            if let cs = cg.colorSpace, cs.model == .rgb { return cs }
            return CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        }()

        guard let context = CGContext(
            data: nil,
            width: pw,
            height: ph,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        let rect = CGRect(x: 0, y: 0, width: pw, height: ph)
        context.interpolationQuality = .high
        context.draw(cg, in: rect)
        context.setBlendMode(.destinationIn)
        context.draw(maskCG, in: rect)

        guard let out = context.makeImage() else { return nil }
        return NSImage(cgImage: out, size: image.size)
    }

    /// ScreenCaptureKit can report the right window frame and output size for
    /// an attached settings sheet while returning an alpha plane whose content
    /// stops well before one edge. Borrowing that alpha as the WindowServer
    /// silhouette then cuts valid pixels out of the frozen display crop.
    ///
    /// A normal rounded window still reaches every image edge somewhere along
    /// that edge; only its corners are transparent. Reject only substantial
    /// full-edge insets, while preserving real interior transparency and small
    /// antialiasing/rounding differences.
    private static func isReliableWindowAlphaMask(
        _ analysis: AlphaMaskAnalysis
    ) -> Bool {
        guard let visibleBounds = analysis.visibleBounds else { return false }

        let width = CGFloat(analysis.mask.width)
        let height = CGFloat(analysis.mask.height)
        let tolerance = max(4, ceil(min(width, height) * 0.01))
        let edgeInsets = [
            visibleBounds.minX,
            visibleBounds.minY,
            width - visibleBounds.maxX,
            height - visibleBounds.maxY
        ]
        return edgeInsets.allSatisfy { $0 <= tolerance }
    }

    /// Shape pixels cropped from the frozen display as a clicked window.
    ///
    /// For an ordinary window, a reliable independent ScreenCaptureKit image
    /// provides the most accurate system corner/transparency mask. Some
    /// attached system sheets return an alpha plane with a substantial empty
    /// edge even though the frozen display crop contains visible window pixels;
    /// `applyingAlphaMask` rejects those malformed silhouettes. A
    /// display-filling window is another special case: its frozen display crop
    /// already defines the full visible target, while the independent-window
    /// alpha can contain compositor-only transparent bands (notably full-screen
    /// Chromium on macOS Tahoe). Applying either unrelated alpha byte-for-byte
    /// punches holes into otherwise valid screen pixels and later clips
    /// annotations to the same holes (issue #153).
    ///
    /// When the selected window spans the display width and at least 90% of its
    /// height, keep the display crop and synthesize only the outer rounded
    /// silhouette. This preserves the normal exact-mask path for ordinary and
    /// partially off-screen windows.
    static func compositedWindowImage(
        snapshotImage: NSImage,
        directWindowImage: NSImage?,
        captureRect: CGRect,
        displayBounds: CGRect
    ) -> NSImage {
        if shouldBorrowDirectWindowAlpha(
            captureRect: captureRect,
            displayBounds: displayBounds
        ),
           let directWindowImage,
           let maskedImage = applyingAlphaMask(from: directWindowImage, to: snapshotImage) {
            return maskedImage
        }

        return roundedCorners(snapshotImage)
    }

    static func shouldBorrowDirectWindowAlpha(
        captureRect: CGRect,
        displayBounds: CGRect
    ) -> Bool {
        let capture = captureRect.standardized
        let display = displayBounds.standardized
        guard capture.width > 0,
              capture.height > 0,
              display.width > 0,
              display.height > 0,
              !capture.isInfinite,
              !display.isInfinite else {
            return true
        }

        let edgeTolerance: CGFloat = 1
        let spansDisplayWidth = capture.minX <= display.minX + edgeTolerance
            && capture.maxX >= display.maxX - edgeTolerance
        let visibleCapture = capture.intersection(display)
        let fillsMostOfDisplayHeight = !visibleCapture.isNull
            && visibleCapture.height >= display.height * 0.9

        return !(spansDisplayWidth && fillsMostOfDisplayHeight)
    }

    private static func continuousCornerMask(
        pixelWidth: Int,
        pixelHeight: Int,
        pointSize: NSSize,
        radiusPoints: CGFloat
    ) -> CGImage? {
        guard pointSize.width > 0, pointSize.height > 0 else { return nil }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        let scaleX = CGFloat(pixelWidth) / pointSize.width
        let scaleY = CGFloat(pixelHeight) / pointSize.height
        let radius = max(0, min(radiusPoints, min(pointSize.width, pointSize.height) / 2))

        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        guard radius > 0 else { return context.makeImage() }

        // CALayer's rounded clipping can have hard coverage when rendered
        // directly into a bitmap. Supersample only the four corner tiles and
        // reduce their alpha to the output pixel grid. The full-size layer
        // preserves macOS's continuous corner shape, while the screenshot
        // itself is never resampled and large captures stay inexpensive.
        let sampleFactor = 4
        let layer = CALayer()
        layer.frame = CGRect(origin: .zero, size: pointSize)
        layer.backgroundColor = NSColor.white.cgColor
        layer.cornerRadius = radius
        layer.cornerCurve = .continuous
        layer.contentsScale = max(scaleX, scaleY) * CGFloat(sampleFactor)
        layer.allowsEdgeAntialiasing = true
        layer.masksToBounds = true

        let tileWidth = min(pixelWidth, Int(ceil(radius * 2 * scaleX)))
        let tileHeight = min(pixelHeight, Int(ceil(radius * 2 * scaleY)))
        context.interpolationQuality = .high
        context.setBlendMode(.copy)
        for y in [0, pixelHeight - tileHeight] {
            for x in [0, pixelWidth - tileWidth] {
                guard let tileContext = CGContext(
                    data: nil,
                    width: tileWidth * sampleFactor,
                    height: tileHeight * sampleFactor,
                    bitsPerComponent: 8,
                    bytesPerRow: 0,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) else { return nil }
                tileContext.setAllowsAntialiasing(true)
                tileContext.setShouldAntialias(true)
                tileContext.scaleBy(
                    x: scaleX * CGFloat(sampleFactor),
                    y: scaleY * CGFloat(sampleFactor)
                )
                tileContext.translateBy(x: -CGFloat(x) / scaleX, y: -CGFloat(y) / scaleY)
                layer.render(in: tileContext)
                guard let tile = tileContext.makeImage() else { return nil }
                context.draw(tile, in: CGRect(x: x, y: y, width: tileWidth, height: tileHeight))
            }
        }

        return context.makeImage()
    }

    private static func alphaMaskAnalysis(
        from source: CGImage,
        width: Int,
        height: Int
    ) -> AlphaMaskAnalysis? {
        guard width > 0, height > 0 else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var rgba = [UInt8](repeating: 0, count: bytesPerRow * height)

        let drewSource = rgba.withUnsafeMutableBytes { ptr -> Bool in
            guard let context = CGContext(
                data: ptr.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }

            context.clear(CGRect(x: 0, y: 0, width: width, height: height))
            context.interpolationQuality = .high
            context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }

        guard drewSource else { return nil }

        var alpha = [UInt8](repeating: 0, count: width * height)
        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1
        for y in 0..<height {
            let rgbaRow = y * bytesPerRow
            let alphaRow = y * width
            for x in 0..<width {
                let value = rgba[rgbaRow + x * bytesPerPixel + 3]
                alpha[alphaRow + x] = value
                if value > 3 {
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                }
            }
        }

        let data = Data(alpha)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        guard let mask = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        ) else {
            return nil
        }

        let visibleBounds: CGRect? = maxX >= minX && maxY >= minY
            ? CGRect(
                x: minX,
                y: minY,
                width: maxX - minX + 1,
                height: maxY - minY + 1
            )
            : nil
        return AlphaMaskAnalysis(mask: mask, visibleBounds: visibleBounds)
    }

    private static func hasAlpha(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            return false
        default:
            return true
        }
    }

    private static func applyMask(_ mask: CGImage, to image: NSImage) -> NSImage {
        guard let cg = image.cgImagePreservingBacking() else { return image }
        let pw = cg.width
        let ph = cg.height
        guard pw > 0, ph > 0 else { return image }

        // Keep the screenshot's own color space (often Display P3) so the
        // corner mask doesn't shift the gamut.
        let colorSpace: CGColorSpace = {
            if let cs = cg.colorSpace, cs.model == .rgb { return cs }
            return CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        }()

        guard let context = CGContext(
            data: nil,
            width: pw,
            height: ph,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return image
        }

        let rect = CGRect(x: 0, y: 0, width: pw, height: ph)
        context.interpolationQuality = .high
        context.clip(to: rect, mask: mask)
        context.draw(cg, in: rect)

        guard let out = context.makeImage() else { return image }
        return NSImage(cgImage: out, size: image.size)
    }

    /// Draw `image` (already corner-masked) onto a larger transparent canvas
    /// with a soft drop shadow. `size` is the shadow magnitude in points —
    /// larger values blur wider and offset further, so the window reads as
    /// floating higher above the background. `size <= 0` is a no-op.
    static func withShadow(_ image: NSImage, size: CGFloat) -> NSImage {
        guard size > 0, let shadowSource = image.cgImagePreservingBacking() else { return image }

        let pxScale = scale(of: image)
        let padding = shadowPadding(forSize: size)
        let padLeft = padding.left
        let padRight = padding.right
        let padTop = padding.top
        let padBottom = padding.bottom

        let canvasSize = NSSize(
            width: image.size.width + padLeft + padRight,
            height: image.size.height + padTop + padBottom
        )
        let pixelW = Int((canvasSize.width * pxScale).rounded())
        let pixelH = Int((canvasSize.height * pxScale).rounded())
        guard pixelW > 0, pixelH > 0 else { return image }

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelW,
            pixelsHigh: pixelH,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return image
        }
        rep.size = canvasSize

        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return image }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high

        let drawRect = NSRect(
            x: padLeft,
            y: padBottom,
            width: image.size.width,
            height: image.size.height
        )
        drawShadow(image: shadowSource, sourceRect: drawRect, size: size, context: context.cgContext)

        image.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)

        NSGraphicsContext.restoreGraphicsState()

        let out = NSImage(size: canvasSize)
        out.addRepresentation(rep)
        return out
    }

    /// Cast from the image's actual alpha in both window and beautify output.
    /// Raw bitmap callers supply their point-to-pixel scale; AppKit contexts
    /// already establish a point-based shadow space.
    static func drawShadow(
        image: CGImage,
        sourceRect: CGRect,
        size: CGFloat,
        baseScale: CGSize = CGSize(width: 1, height: 1),
        context: CGContext
    ) {
        for layer in layers(forShadowSize: size) {
            drawShadowOnly(
                image: image, sourceRect: sourceRect, layer: layer,
                baseScale: baseScale, context: context
            )
        }
    }

    private static func layers(forShadowSize size: CGFloat) -> [ShadowLayer] {
        let s = max(size, 0)
        guard s > 0 else { return [] }

        return [
            // Tight ambient bloom keeps depth visible without forcing a large
            // transparent border around the exported screenshot.
            ShadowLayer(
                blur: s * 0.45,
                opacity: 0.20,
                offset: .zero
            ),
            // Concentrated key shadow: stronger than the preview, but with
            // less blur so the required output padding stays small.
            ShadowLayer(
                blur: s * 0.52,
                opacity: 0.56,
                offset: CGSize(width: 0, height: -s * 0.24)
            ),
            // A crisp contact layer gives the edge weight after the wider
            // shadow fringe has been trimmed aggressively.
            ShadowLayer(
                blur: max(s * 0.12, 2),
                opacity: 0.24,
                offset: CGSize(width: 0, height: -max(s * 0.07, 1))
            ),
        ]
    }

    /// Shared by window screenshots and beautify preview/export. The downward
    /// key shadow needs more room below the image than above it.
    static func shadowPadding(forSize size: CGFloat) -> NSEdgeInsets {
        let outsets = shadowOutsets(for: layers(forShadowSize: size))
        return NSEdgeInsets(
            top: ceil(outsets.top), left: ceil(outsets.left),
            bottom: ceil(outsets.bottom), right: ceil(outsets.right)
        )
    }

    private static func shadowOutsets(
        for layers: [ShadowLayer]
    ) -> (left: CGFloat, right: CGFloat, top: CGFloat, bottom: CGFloat) {
        var left: CGFloat = 0
        var right: CGFloat = 0
        var top: CGFloat = 0
        var bottom: CGFloat = 0

        for layer in layers {
            let fringe = shadowFringe(forBlur: layer.blur)
            left = max(left, fringe + max(-layer.offset.width, 0))
            right = max(right, fringe + max(layer.offset.width, 0))
            top = max(top, fringe + max(layer.offset.height, 0))
            bottom = max(bottom, fringe + max(-layer.offset.height, 0))
        }

        return (left, right, top, bottom)
    }

    private static func shadowFringe(forBlur blur: CGFloat) -> CGFloat {
        blur * 1.2 + 5
    }

    private static func drawShadowOnly(
        image: CGImage,
        sourceRect: CGRect,
        layer: ShadowLayer,
        baseScale: CGSize,
        context: CGContext
    ) {
        let clipOutset = shadowFringe(forBlur: layer.blur)
            + max(abs(layer.offset.width), abs(layer.offset.height))
        let clipRect = sourceRect.insetBy(dx: -clipOutset, dy: -clipOutset)
        let displacement = clipRect.width + clipOutset

        // Cast from the window's actual alpha, including its antialiased
        // continuous corners, instead of imposing a fixed circular silhouette.
        // Move the opaque source out of view so it cannot leave a black rim.
        context.saveGState()
        context.clip(to: clipRect)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.saveGState()
        context.interpolationQuality = .high
        context.setShadow(
            offset: CGSize(
                width: (layer.offset.width - displacement) * baseScale.width,
                height: layer.offset.height * baseScale.height
            ),
            blur: layer.blur * max(baseScale.width, baseScale.height),
            color: NSColor.black.withAlphaComponent(layer.opacity).cgColor
        )
        context.draw(image, in: sourceRect.offsetBy(dx: displacement, dy: 0))

        // Keep the shadow hollow using fractional alpha coverage, avoiding
        // the jagged inverse path clip used by the previous renderer.
        context.setShadow(offset: .zero, blur: 0, color: nil)
        context.setBlendMode(.destinationOut)
        context.draw(image, in: sourceRect)
        context.restoreGState()
        context.endTransparencyLayer()
        context.restoreGState()
    }
}
