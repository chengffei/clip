import AppKit

enum HistoryMediaBadgeKind {
    case gif
    case mp4
    case files(String)

    init?(entry: HistoryEntry) {
        switch entry.kind {
        case .image where entry.fileURL.pathExtension.lowercased() == "gif":
            self = .gif
        case .video:
            self = .mp4
        case .files(let files):
            self = .files(files.typeLabel)
        case .image, .color, .text:
            return nil
        }
    }

    var title: String {
        switch self {
        case .gif: return "GIF"
        case .mp4: return "MP4"
        case .files(let title): return title
        }
    }
}

final class HistoryMediaBadgeView: NSView {
    private let label = NSTextField(labelWithString: "")
    private let iconView = NSImageView()
    private var labelLeadingConstraint: NSLayoutConstraint?
    private var isFileReference = false

    init(kind: HistoryMediaBadgeKind? = nil) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = accentGreen.withAlphaComponent(0.92).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.black.withAlphaComponent(0.18).cgColor

        label.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .bold)
        label.textColor = .black
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        iconView.image = NSImage(systemSymbolName: "doc", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold))
        iconView.image?.isTemplate = true
        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.isHidden = true
        addSubview(iconView)

        let leading = label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7)
        labelLeadingConstraint = leading
        NSLayoutConstraint.activate([
            leading,
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 11),
            iconView.heightAnchor.constraint(equalToConstant: 11)
        ])

        if let kind {
            configure(kind: kind)
        }
    }

    func configure(kind: HistoryMediaBadgeKind) {
        if case .files = kind {
            isFileReference = true
        } else {
            isFileReference = false
        }
        label.stringValue = kind.title
        iconView.isHidden = !isFileReference
        labelLeadingConstraint?.constant = isFileReference ? 22 : 7
        layer?.cornerRadius = isFileReference ? 5 : 6
        layer?.backgroundColor = isFileReference
            ? NSColor(srgbRed: 37.0 / 255, green: 61.0 / 255, blue: 86.0 / 255, alpha: 1).cgColor
            : accentGreen.withAlphaComponent(0.92).cgColor
        layer?.borderColor = isFileReference
            ? NSColor(srgbRed: 80.0 / 255, green: 110.0 / 255, blue: 140.0 / 255, alpha: 1).cgColor
            : NSColor.black.withAlphaComponent(0.18).cgColor
        label.textColor = isFileReference
            ? NSColor(srgbRed: 170.0 / 255, green: 214.0 / 255, blue: 1, alpha: 1)
            : .black
        iconView.contentTintColor = label.textColor
        label.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: isFileReference ? .semibold : .bold)
        setAccessibilityLabel(kind.title)
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        let labelSize = label.intrinsicContentSize
        return NSSize(width: ceil(labelSize.width) + (isFileReference ? 29 : 14), height: 18)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

final class HistoryCloudBadgeView: NSView {
    private let label = NSTextField(labelWithString: "☁️")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        label.font = NSFont.systemFont(ofSize: 15, weight: .regular)
        label.alignment = .center
        label.isSelectable = false
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -0.5)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 24, height: 22)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

enum HistoryItemCornerControlMetrics {
    static let size: CGFloat = 18
    static let favoriteSymbolPointSize: CGFloat = 14
    static let horizontalPreviewOverlap: CGFloat = 5
    static let favoritePreviewOverlap: CGFloat = 7
}

final class HistoryFavoriteButton: NSButton {
    static func symbolName(isFavorite: Bool) -> String {
        isFavorite ? "star.fill" : "star"
    }

    static func shouldBeVisible(isFavorite: Bool, isHovered: Bool) -> Bool {
        isFavorite || isHovered
    }

    var isFavorite = false {
        didSet { updateAppearance() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = HistoryItemCornerControlMetrics.size / 2
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.46).cgColor
        isBordered = false
        setButtonType(.momentaryChange)
        imagePosition = .imageOnly
        imageScaling = .scaleProportionallyDown
        focusRingType = .none
        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(
            width: HistoryItemCornerControlMetrics.size,
            height: HistoryItemCornerControlMetrics.size
        )
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func updateAccessibilityLabel(_ label: String) {
        toolTip = label
        setAccessibilityLabel(label)
    }

    private func updateAppearance() {
        let symbolName = Self.symbolName(isFavorite: isFavorite)
        let config = NSImage.SymbolConfiguration(
            pointSize: HistoryItemCornerControlMetrics.favoriteSymbolPointSize,
            weight: .semibold
        )
        image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        image?.isTemplate = true
        contentTintColor = isFavorite
            ? accentGreen.withAlphaComponent(0.98)
            : NSColor.white.withAlphaComponent(0.88)
    }
}
