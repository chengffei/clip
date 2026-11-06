import AppKit

/// Rounded surface for floating controls (recording HUD, pin hover toolbar).
///
/// On macOS 26+ the background is system Liquid Glass (`NSGlassEffectView`,
/// regular style), which already adapts to Reduce Transparency and Increase
/// Contrast. Earlier systems fall back to a behind-window visual effect
/// material. Controls go in `contentView` so they sit inside the glass.
final class GlassChromeView: NSView {
    let contentView = NSView()
    private let backgroundView: NSView

    /// Corner radius; `nil` means a capsule (half the height).
    var cornerRadius: CGFloat? {
        didSet { needsLayout = true }
    }

    init(cornerRadius: CGFloat? = nil, interactive: Bool = true) {
        self.cornerRadius = cornerRadius
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            if #available(macOS 27.0, *) {
                glass.effectIsInteractive = interactive
            }
            glass.contentView = contentView
            backgroundView = glass
        } else {
            let effect = NSVisualEffectView()
            effect.material = .popover
            effect.blendingMode = .behindWindow
            effect.state = .active
            effect.wantsLayer = true
            effect.layer?.cornerCurve = .continuous
            effect.layer?.masksToBounds = true
            effect.layer?.borderWidth = Brand.hairline
            effect.addSubview(contentView)
            backgroundView = effect
        }
        super.init(frame: .zero)
        wantsLayer = true
        addSubview(backgroundView)
        applyAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var resolvedCornerRadius: CGFloat {
        cornerRadius ?? bounds.height / 2
    }

    override func layout() {
        super.layout()
        backgroundView.frame = bounds
        contentView.frame = bounds
        let radius = resolvedCornerRadius
        if #available(macOS 26.0, *), let glass = backgroundView as? NSGlassEffectView {
            glass.cornerRadius = radius
        } else {
            backgroundView.layer?.cornerRadius = radius
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyAppearance()
    }

    /// Only the pre-26 fallback draws its own hairline; glass has its own edge.
    private func applyAppearance() {
        guard backgroundView is NSVisualEffectView else { return }
        backgroundView.layer?.borderColor = AdaptiveChrome.resolvedCGColor(
            AdaptiveChrome.border,
            for: effectiveAppearance
        )
    }
}
