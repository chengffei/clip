import AppKit

/// Shared semantic colors for capcap's floating dialogs and editor chrome
///
/// AppKit semantic colors already follow the effective appearance when they
/// are used for text or drawing. Layer colors are different: assigning a
/// `CGColor` resolves the color once, so layer-backed views must resolve again
/// from `viewDidChangeEffectiveAppearance`
enum AdaptiveChrome {
    static let floatingBackground = NSColor(
        name: NSColor.Name("clip.floatingBackground")
    ) { _ in
        Brand.inkFloating
    }

    static let toolbarBackground = NSColor(
        name: NSColor.Name("clip.toolbarBackground")
    ) { _ in
        Brand.inkFloating
    }

    static let panelBackground = NSColor(
        name: NSColor.Name("clip.panelBackground")
    ) { _ in
        Brand.ink
    }

    static let popoverBackground = NSColor(
        name: NSColor.Name("clip.popoverBackground")
    ) { _ in
        Brand.inkRaised
    }

    static let cardBackground = NSColor(
        name: NSColor.Name("clip.cardBackground")
    ) { _ in
        Brand.subtleFill
    }

    static let border = NSColor(
        name: NSColor.Name("clip.border")
    ) { _ in
        Brand.line
    }

    static let subtleFill = NSColor(
        name: NSColor.Name("clip.subtleFill")
    ) { _ in
        Brand.subtleFill
    }

    static let selectedFill = NSColor(
        name: NSColor.Name("clip.selectedFill")
    ) { _ in
        Brand.accentFill
    }

    static let separator = NSColor(
        name: NSColor.Name("clip.separator")
    ) { _ in
        Brand.lineStrong
    }

    static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    static func resolvedColor(_ color: NSColor, for appearance: NSAppearance) -> NSColor {
        var resolved = color
        appearance.performAsCurrentDrawingAppearance {
            resolved = color.usingColorSpace(.deviceRGB) ?? color
        }
        return resolved
    }

    static func resolvedCGColor(_ color: NSColor, for appearance: NSAppearance) -> CGColor {
        resolvedColor(color, for: appearance).cgColor
    }
}

/// Shared geometry and surface metrics for compact floating operation bars
/// such as the recording HUD and the PIN image toolbar
enum FloatingControlChrome {
    static let height: CGFloat = 32
    static let buttonSide: CGFloat = 24
    static let cornerRadius: CGFloat = Brand.radius
    static let borderWidth: CGFloat = Brand.hairline
    static let gap: CGFloat = 8
    static let screenEdgeInset: CGFloat = 4

    static func origin(
        for size: NSSize,
        relativeTo anchorRect: NSRect,
        visibleFrame: NSRect?
    ) -> NSPoint {
        var origin = NSPoint(
            x: anchorRect.maxX - size.width - gap,
            y: anchorRect.maxY + gap
        )

        guard let visibleFrame else { return origin }
        if origin.y + size.height > visibleFrame.maxY {
            origin.y = anchorRect.minY - size.height - gap
        }
        origin.x = max(
            visibleFrame.minX + screenEdgeInset,
            min(origin.x, visibleFrame.maxX - size.width - screenEdgeInset)
        )
        origin.y = max(
            visibleFrame.minY + screenEdgeInset,
            min(origin.y, visibleFrame.maxY - size.height - screenEdgeInset)
        )
        return origin
    }
}

/// Layer-backed rounded surface whose colors continue to follow live system
/// appearance changes
final class AdaptiveChromeSurfaceView: NSView {
    enum Style {
        case floating
        case toolbar
        case panel
        case popover
        case card

        var backgroundColor: NSColor {
            switch self {
            case .floating: return AdaptiveChrome.floatingBackground
            case .toolbar: return AdaptiveChrome.toolbarBackground
            case .panel: return AdaptiveChrome.panelBackground
            case .popover: return AdaptiveChrome.popoverBackground
            case .card: return AdaptiveChrome.cardBackground
            }
        }
    }

    var style: Style {
        didSet { applyAppearance() }
    }
    var cornerRadius: CGFloat {
        didSet { layer?.cornerRadius = cornerRadius }
    }
    var borderWidth: CGFloat {
        didSet { layer?.borderWidth = borderWidth }
    }

    init(style: Style, cornerRadius: CGFloat = 0, borderWidth: CGFloat = 0) {
        self.style = style
        self.cornerRadius = cornerRadius
        self.borderWidth = borderWidth
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = cornerRadius > 0
        applyAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyAppearance()
    }

    private func applyAppearance() {
        guard let layer else { return }
        layer.cornerRadius = cornerRadius
        layer.borderWidth = borderWidth
        layer.backgroundColor = AdaptiveChrome.resolvedCGColor(style.backgroundColor, for: effectiveAppearance)
        layer.borderColor = AdaptiveChrome.resolvedCGColor(AdaptiveChrome.border, for: effectiveAppearance)
    }
}

/// A one-pixel semantic separator for layer-composited HUD layouts
final class AdaptiveSeparatorView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        applyAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyAppearance()
    }

    private func applyAppearance() {
        layer?.backgroundColor = AdaptiveChrome.resolvedCGColor(
            AdaptiveChrome.separator,
            for: effectiveAppearance
        )
    }
}
