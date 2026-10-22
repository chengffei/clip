import AppKit
import CoreGraphics

/// Wraps `EditCanvasView` as a subview. When a beautify preset is set, the
/// container grows by the window shadow's per-edge margins, repositions the
/// canvas at `(left, bottom)`, and draws the gradient background + inner shadow +
/// base screenshot behind the canvas. Rotation and display scaling preserve
/// the canvas's logical bounds so tools, hit tests, and editable text retain
/// their document coordinates in every orientation.
final class BeautifyContainerView: NSView {
    private(set) weak var canvasView: EditCanvasView?
    private(set) var beautifyPreset: BeautifyPreset?

    /// Cached wallpaper image for the wallpaper preset.
    var wallpaperImage: NSImage?

    // Reuse the alpha mask while the slider moves; rebuilding a full-resolution
    // rotated/masked image on every draw would make shadow adjustment expensive.
    private var cachedShadowImage: NSImage?
    private var cachedShadowRotation: ImageRotation = .none
    private var cachedShadowCornerRadius: CGFloat?
    private var cachedShadowSource: CGImage?

    private(set) var shadowSize: CGFloat = BeautifyRenderer.shadowSizeDefault

    var contentPadding: NSEdgeInsets {
        guard isBeautifyEnabled else { return NSEdgeInsetsZero }
        return BeautifyRenderer.padding(forShadowSize: shadowSize, shadowEnabled: true)
    }

    var isBeautifyEnabled: Bool { beautifyPreset != nil }

    var innerImageSize: CGSize {
        canvasView?.orientedDisplaySize ?? .zero
    }

    var outerSize: CGSize { frame.size }

    init(canvasView: EditCanvasView) {
        self.canvasView = canvasView
        super.init(frame: NSRect(origin: .zero, size: canvasView.frame.size))
        addSubview(canvasView)
        canvasView.setFrameOrigin(.zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // Let mouse events route normally to the canvas subview.
    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point)
    }

    override var isFlipped: Bool { false }

    // MARK: - Beautify API

    func setBeautify(preset: BeautifyPreset?) {
        beautifyPreset = preset
        if preset == nil {
            cachedShadowImage = nil
            cachedShadowSource = nil
        }
        // A beautify preset owns the area behind the canvas (gradient,
        // wallpaper, or its own checkerboard). In normal editing the canvas
        // supplies a stable transparency preview instead of exposing the
        // frozen desktop snapshot beneath it.
        canvasView?.drawsTransparencyBackdrop = preset == nil
        relayout()
        needsDisplay = true
    }

    func setShadowSize(_ size: CGFloat) {
        let size = BeautifyRenderer.normalizedShadowSize(size)
        guard shadowSize != size else { return }
        shadowSize = size
        relayout()
        needsDisplay = true
    }

    /// Called by the controller when the canvas's intrinsic size changes
    /// (selection resize or long-screenshot preview load).
    func canvasSizeDidChange() {
        if let canvasView {
            canvasView.setPresentationScale(canvasView.presentationScale)
        }
        relayout()
        needsDisplay = true
    }

    private func relayout() {
        guard let canvasView else { return }
        let inner = canvasView.orientedDisplaySize
        let padding: NSEdgeInsets
        let newSize: CGSize
        if beautifyPreset != nil, inner.width > 0, inner.height > 0 {
            padding = contentPadding
            newSize = CGSize(
                width: inner.width + padding.left + padding.right,
                height: inner.height + padding.top + padding.bottom
            )
        } else {
            padding = NSEdgeInsetsZero
            newSize = inner
        }
        if frame.size != newSize {
            setFrameSize(newSize)
        }
        // frameRotation rotates around the frame origin. Locate the actual
        // rotated bounds before translating them into the inner card rect.
        let rotatedBounds = canvasView.convert(canvasView.bounds, to: self)
        let origin = NSPoint(
            x: canvasView.frame.origin.x + padding.left - rotatedBounds.minX,
            y: canvasView.frame.origin.y + padding.bottom - rotatedBounds.minY
        )
        if canvasView.frame.origin != origin {
            canvasView.setFrameOrigin(origin)
        }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard
            let preset = beautifyPreset,
            let canvasView,
            let context = NSGraphicsContext.current?.cgContext
        else { return }

        let inner = canvasView.orientedDisplaySize
        guard inner.width > 0, inner.height > 0 else { return }

        let outerRect = CGRect(origin: .zero, size: bounds.size)
        let innerRect = canvasView.convert(canvasView.bounds, to: self)

        // 1. Background — transparent uses a checkerboard so empty padding
        // and rounded corners are visible; export stays pure alpha.
        if preset.isTransparent {
            BeautifyRenderer.drawCheckerboard(in: outerRect)
        } else if preset.isWallpaper, let wp = wallpaperImage {
            BeautifyRenderer.drawWallpaperBackground(in: outerRect, wallpaper: wp)
        } else {
            BeautifyRenderer.drawBackground(in: outerRect, preset: preset)
        }

        // 2. Use the same image alpha and renderer as window screenshots.
        if let source = shadowSource(for: canvasView) {
            WindowEffects.drawShadow(
                image: source, sourceRect: innerRect, size: shadowSize,
                context: context
            )
        }
    }

    private func shadowSource(for canvasView: EditCanvasView) -> CGImage? {
        // Only use already prepared editor images. Never capture the screen
        // from draw(_:), which could include the editor itself.
        guard let image = canvasView.previewImage ?? canvasView.externalBaseImage
            ?? canvasView.windowBaseImage ?? canvasView.overrideBaseImage else { return nil }
        let rotation = canvasView.imageRotation
        let radius = canvasView.beautifyCornerRadius
        if cachedShadowImage === image, cachedShadowRotation == rotation,
           cachedShadowCornerRadius == radius, let cachedShadowSource {
            return cachedShadowSource
        }
        guard let oriented = rotation.render(image),
              let backing = oriented.cgImagePreservingBacking(),
              let source = BeautifyRenderer.shadowSource(
                from: backing, imageSize: oriented.size, cornerRadius: radius
              ) else { return nil }
        cachedShadowImage = image
        cachedShadowRotation = rotation
        cachedShadowCornerRadius = radius
        cachedShadowSource = source
        return source
    }
}
