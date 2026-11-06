import AppKit

/// Surfaces for the capture overlay's floating controls: the annotation
/// toolbar, its sub-toolbars, the hover tooltip and the toast.
///
/// They float over arbitrary screen content, which is the controls layer the
/// HIG reserves Liquid Glass for. On macOS 26+ they sit on regular glass; with
/// Reduce Transparency on (or before macOS 26) they fall back to the opaque
/// Brand plate, with a stronger outline when Increase Contrast is on.
enum CaptureChrome {
    /// Inset of the toolbar plate inside the toolbar view's bounds.
    static let plateInset: CGFloat = 2

    static var usesGlass: Bool {
        guard #available(macOS 26, *) else { return false }
        return !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }

    static var increasesContrast: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    }

    /// Light tint over the toolbar glass. The toolbar floats outside the
    /// selection, on the 40–62 % black capture scrim; untinted regular glass
    /// takes on that darkness and the dark glyphs sink into it (Felix,
    /// 2026-11-06: "灰暗，看图标费劲"). The tint keeps the glass bright and
    /// legible over any backdrop while it still refracts and catches light.
    static let glassTint = NSColor.white.withAlphaComponent(0.25)

    /// Frosted base under the glass. Regular glass adapts to how bright the
    /// backdrop is, so a tint alone still went grey over the scrim; with this
    /// base the glass samples a light surface and stays bright, while its
    /// edges keep refracting and catching highlights.
    static let glassBaseAlpha: CGFloat = 0.72

    /// Wraps `view`'s controls in Liquid Glass: the glass fills the bounds and
    /// the existing subviews move into its content view, so they sit inside
    /// the material (as system toolbars do) rather than on top of it. On
    /// macOS 27 the glass reacts to the pointer. Returns false (and installs
    /// nothing) when glass is not in use.
    @discardableResult
    static func installGlassBackground(in view: NSView, inset: CGFloat = plateInset, cornerRadius: CGFloat) -> Bool {
        guard usesGlass, #available(macOS 26, *) else { return false }
        guard !hasGlassBackground(view) else { return true }
        // Fill the whole bounds so moved subviews keep their coordinates.
        let glass = CaptureGlassBackdrop(frame: view.bounds)
        glass.style = .regular
        glass.cornerRadius = cornerRadius + inset
        glass.tintColor = glassTint
        if #available(macOS 27, *) { glass.effectIsInteractive = true }
        glass.autoresizingMask = [.width, .height]
        let content = PassThroughContentView(frame: glass.bounds)
        content.autoresizingMask = [.width, .height]
        for sub in view.subviews { sub.removeFromSuperview(); content.addSubview(sub) }
        glass.contentView = content
        let base = NSView(frame: view.bounds)
        base.wantsLayer = true
        base.layer?.backgroundColor = NSColor.white.withAlphaComponent(glassBaseAlpha).cgColor
        base.layer?.cornerRadius = cornerRadius + inset
        base.layer?.cornerCurve = .continuous
        base.autoresizingMask = [.width, .height]
        view.addSubview(base)
        view.addSubview(glass)
        return true
    }

    static func hasGlassBackground(_ view: NSView) -> Bool {
        guard #available(macOS 26, *) else { return false }
        return view.subviews.contains { $0 is CaptureGlassBackdrop }
    }

    /// Opaque plate used when glass is unavailable. A no-op when `view`
    /// already has a glass backdrop.
    static func drawPlate(for view: NSView, in rect: NSRect, cornerRadius: CGFloat) {
        guard !hasGlassBackground(view) else { return }
        let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
        AdaptiveChrome.toolbarBackground.setFill()
        path.fill()
        (increasesContrast ? Brand.lineStrong : Brand.line).setStroke()
        path.lineWidth = Brand.hairline
        path.stroke()
    }

    /// Content view for a borderless chip window (tooltip, toast): glass with
    /// `content` inside, or `content` drawing its own opaque plate.
    static func chipContentView(content: NSView, cornerRadius: CGFloat) -> NSView {
        guard usesGlass, #available(macOS 26, *) else { return content }
        let host = NSView(frame: content.frame)
        let base = NSView(frame: host.bounds)
        base.wantsLayer = true
        base.layer?.backgroundColor = NSColor.white.withAlphaComponent(glassBaseAlpha).cgColor
        base.layer?.cornerRadius = cornerRadius
        base.layer?.cornerCurve = .continuous
        base.autoresizingMask = [.width, .height]
        let glass = NSGlassEffectView(frame: host.bounds)
        glass.style = .regular
        glass.cornerRadius = cornerRadius
        glass.tintColor = glassTint
        glass.autoresizingMask = [.width, .height]
        content.frame = glass.bounds
        content.autoresizingMask = [.width, .height]
        glass.contentView = content
        host.addSubview(base)
        host.addSubview(glass)
        return host
    }

    /// Opaque chip plate for the fallback path; skipped when the chip is
    /// hosted in glass.
    static func drawChipPlateIfNeeded(for view: NSView, cornerRadius: CGFloat) {
        if #available(macOS 26, *) {
            var ancestor = view.superview
            while let current = ancestor {
                if current is NSGlassEffectView { return }
                ancestor = current.superview
            }
        }
        let path = NSBezierPath(
            roundedRect: view.bounds.insetBy(dx: 0.5, dy: 0.5),
            xRadius: cornerRadius,
            yRadius: cornerRadius
        )
        AdaptiveChrome.floatingBackground.setFill()
        path.fill()
        (increasesContrast ? Brand.lineStrong : AdaptiveChrome.border).setStroke()
        path.lineWidth = Brand.hairline
        path.stroke()
    }
}

/// Glass that holds the toolbar's controls. A click on a control reaches it;
/// a click between controls passes through to the toolbar view underneath,
/// exactly as before the glass existed.
@available(macOS 26, *)
private final class CaptureGlassBackdrop: NSGlassEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return (hit === self || hit === contentView) ? nil : hit
    }
}

private final class PassThroughContentView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }
}
