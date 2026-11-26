import AppKit

/// Loupe shown while a selection edge or corner is dragged.
///
/// Magnifies the frozen desktop around the point being moved, with a pixel
/// grid and the outside of the selection dimmed, so the user can see exactly
/// which pixel row or column the edge sits on. Follows the convention of
/// Snipaste, PixPin and Shottr: appears only during the drag, never takes
/// input, and sits next to the cursor on the selection's inner side so it
/// does not cover the content the edge is being dragged toward.
final class EdgeLoupeWindow: NSPanel {
    static let lensSize: CGFloat = 120
    /// Device pixels shown across the lens. Odd so one pixel sits centered.
    static let pixelsAcross: CGFloat = 15
    /// Gap between the cursor and the nearest lens edge.
    static let cursorGap: CGFloat = 18
    private static let screenMargin: CGFloat = 6

    private let loupeView: EdgeLoupeView

    init() {
        let frame = NSRect(x: 0, y: 0, width: Self.lensSize, height: Self.lensSize)
        loupeView = EdgeLoupeView(frame: frame)
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        // Above the editor's frame and toolbar windows (up to screenSaver + 4).
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 5)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        ignoresMouseEvents = true
        sharingType = .none
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = loupeView
    }

    /// - Parameters:
    ///   - image: frozen desktop covering `imageBounds` (view points).
    ///   - anchor: the point on the dragged edge to center on (view points).
    ///   - selection: current selection rect (view points).
    ///   - placement: unit direction from the cursor toward the lens.
    ///   - cursor: cursor location in global screen coordinates.
    ///   - screenFrame: frame of the screen the drag happens on.
    func update(
        image: CGImage,
        imageBounds: NSRect,
        anchor: NSPoint,
        selection: NSRect,
        placement: CGVector,
        cursor: NSPoint,
        screenFrame: NSRect
    ) {
        loupeView.configure(image: image, imageBounds: imageBounds, anchor: anchor, selection: selection)
        setFrameOrigin(Self.origin(cursor: cursor, placement: placement, screenFrame: screenFrame))
        if !isVisible { orderFrontRegardless() }
    }

    func dismiss() {
        orderOut(nil)
        loupeView.clear()
    }

    /// Places the lens `cursorGap` away from the cursor along `placement`,
    /// flipping an axis when the lens would leave the screen.
    static func origin(cursor: NSPoint, placement: CGVector, screenFrame: NSRect) -> NSPoint {
        let size = lensSize
        let reach = cursorGap + size / 2
        func axis(_ c: CGFloat, _ d: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
            var center = c + d * reach
            if d != 0, center - size / 2 < lo + screenMargin || center + size / 2 > hi - screenMargin {
                center = c - d * reach
            }
            let minOrigin = lo + screenMargin
            let maxOrigin = hi - screenMargin - size
            return max(minOrigin, min(maxOrigin, center - size / 2))
        }
        return NSPoint(
            x: axis(cursor.x, placement.dx, screenFrame.minX, screenFrame.maxX),
            y: axis(cursor.y, placement.dy, screenFrame.minY, screenFrame.maxY)
        )
    }
}

final class EdgeLoupeView: NSView {
    private var image: CGImage?
    private var imageBounds: NSRect = .zero
    private var anchor: NSPoint = .zero
    private var selection: NSRect = .zero

    private static let cornerRadius: CGFloat = 10

    func configure(image: CGImage, imageBounds: NSRect, anchor: NSPoint, selection: NSRect) {
        self.image = image
        self.imageBounds = imageBounds
        self.anchor = anchor
        self.selection = selection
        needsDisplay = true
    }

    func clear() {
        image = nil
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let lens = bounds
        let shape = CGPath(roundedRect: lens, cornerWidth: Self.cornerRadius, cornerHeight: Self.cornerRadius, transform: nil)

        context.saveGState()
        context.addPath(shape)
        context.clip()
        context.setFillColor(NSColor(white: 0.12, alpha: 1).cgColor)
        context.fill(lens)
        if let image, imageBounds.width > 0 {
            drawContent(image: image, in: context, lens: lens)
        }
        context.restoreGState()

        // Rim: a dark hairline outside a white one, visible on any content.
        context.setLineWidth(1)
        context.setStrokeColor(NSColor.black.withAlphaComponent(0.28).cgColor)
        context.addPath(CGPath(roundedRect: lens.insetBy(dx: 0.5, dy: 0.5), cornerWidth: Self.cornerRadius - 0.5, cornerHeight: Self.cornerRadius - 0.5, transform: nil))
        context.strokePath()
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.7).cgColor)
        context.addPath(CGPath(roundedRect: lens.insetBy(dx: 1.5, dy: 1.5), cornerWidth: Self.cornerRadius - 1.5, cornerHeight: Self.cornerRadius - 1.5, transform: nil))
        context.strokePath()
    }

    private func drawContent(image: CGImage, in context: CGContext, lens: NSRect) {
        // Device pixels per view point, and lens points per device pixel.
        let scale = CGFloat(image.width) / imageBounds.width
        let cell = lens.width / EdgeLoupeWindow.pixelsAcross
        let mid = NSPoint(x: lens.midX, y: lens.midY)
        // Anchor in pixel space, x right / y up from the image's bottom.
        let px = (anchor.x - imageBounds.minX) * scale
        let pyUp = (anchor.y - imageBounds.minY) * scale
        let imageHeight = CGFloat(image.height)
        let half = EdgeLoupeWindow.pixelsAcross / 2 + 1

        // Integer crop around the anchor; cropping shares the image's buffer.
        let x0 = max(0, floor(px - half))
        let x1 = min(CGFloat(image.width), ceil(px + half))
        let top = max(0, floor(imageHeight - pyUp - half))      // y-down rows
        let bottom = min(imageHeight, ceil(imageHeight - pyUp + half))
        if x1 > x0, bottom > top,
           let crop = image.cropping(to: CGRect(x: x0, y: top, width: x1 - x0, height: bottom - top)) {
            let drawRect = NSRect(
                x: mid.x + (x0 - px) * cell,
                y: mid.y + ((imageHeight - bottom) - pyUp) * cell,
                width: (x1 - x0) * cell,
                height: (bottom - top) * cell
            )
            context.interpolationQuality = .none
            context.draw(crop, in: drawRect)
        }

        // Pixel grid.
        context.setLineWidth(1)
        context.setStrokeColor(NSColor(white: 0.5, alpha: 0.22).cgColor)
        let firstColumn = floor(px - half), lastColumn = ceil(px + half)
        var i = firstColumn
        while i <= lastColumn {
            let x = (mid.x + (i - px) * cell).rounded() + 0.5
            context.move(to: CGPoint(x: x, y: lens.minY))
            context.addLine(to: CGPoint(x: x, y: lens.maxY))
            i += 1
        }
        let firstRow = floor(pyUp - half), lastRow = ceil(pyUp + half)
        i = firstRow
        while i <= lastRow {
            let y = (mid.y + (i - pyUp) * cell).rounded() + 0.5
            context.move(to: CGPoint(x: lens.minX, y: y))
            context.addLine(to: CGPoint(x: lens.maxX, y: y))
            i += 1
        }
        context.strokePath()

        // Same dimming as the overlay outside the selection, then the edge.
        let zoom = scale * cell
        let selectionInLens = NSRect(
            x: mid.x + (selection.minX - anchor.x) * zoom,
            y: mid.y + (selection.minY - anchor.y) * zoom,
            width: selection.width * zoom,
            height: selection.height * zoom
        )
        let dim = CGMutablePath()
        dim.addRect(lens)
        dim.addRect(selectionInLens)
        context.addPath(dim)
        context.setFillColor(NSColor.black.withAlphaComponent(0.4).cgColor)
        context.fillPath(using: .evenOdd)

        context.setStrokeColor(Brand.accent.cgColor)
        context.setLineWidth(1.5)
        context.stroke(selectionInLens)
    }
}
