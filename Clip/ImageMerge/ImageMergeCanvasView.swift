import AppKit

private func isImageMergeSelectionDeleteKey(_ event: NSEvent) -> Bool {
    let blockedModifiers: NSEvent.ModifierFlags = [.command, .control, .option]
    let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    guard modifiers.intersection(blockedModifiers).isEmpty else { return false }
    return event.keyCode == 51 || event.keyCode == 117
}

final class ImageMergeCanvasView: NSView {
    var document: ImageMergeDocument? {
        didSet {
            needsDisplay = true
        }
    }
    var onImportURLs: (([URL]) -> Void)?
    var onDocumentChanged: (() -> Void)?

    private enum DragMode {
        case move(id: UUID, startPoint: NSPoint, startOffset: NSPoint)
        case resize(id: UUID, startPoint: NSPoint, startScale: CGFloat, center: NSPoint)
    }

    private enum SnapGuideStyle {
        case alignment
        case spacing
    }

    private struct SnapGuide {
        let start: NSPoint
        let end: NSPoint
        let style: SnapGuideStyle
    }

    private struct SnapAxisCandidate {
        let delta: CGFloat
        let distance: CGFloat
        let priority: Int
        let guides: [SnapGuide]
    }

    private struct GapReference {
        let gap: CGFloat
        let leading: NSRect
        let trailing: NSRect
    }

    private var dragMode: DragMode?
    private var activeGuides: [SnapGuide] = []
    private let snapThresholdInScreenPoints: CGFloat = 8
    private let guideExtension: CGFloat = 28

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()

        guard let document else { return }
        if document.items.isEmpty {
            drawEmptyState()
            return
        }

        let insetRect = bounds.insetBy(dx: 28, dy: 28)
        ImageMergeRenderer.drawPreview(
            document: document,
            in: insetRect,
            selectedItemID: document.selectedItemID
        )

        if let geometry = currentGeometry() {
            drawCanvasSizeLabel(
                canvasSize: geometry.layout.canvasSize,
                near: geometry.outputRect
            )

            if !activeGuides.isEmpty {
                drawGuides(
                    activeGuides,
                    outputRect: geometry.outputRect,
                    scale: geometry.scale
                )
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        activeGuides.removeAll()
        guard let document,
              !document.items.isEmpty,
              let geometry = currentGeometry()
        else {
            needsDisplay = true
            return
        }

        window?.makeFirstResponder(self)
        let viewPoint = convert(event.locationInWindow, from: nil)
        let layoutPoint = ImageMergeRenderer.layoutPoint(
            from: viewPoint,
            outputRect: geometry.outputRect,
            scale: geometry.scale,
            canvasHeight: geometry.layout.canvasSize.height
        )

        for itemLayout in geometry.layout.itemLayouts.reversed() {
            let previewRect = ImageMergeRenderer.previewRect(
                for: itemLayout.imageRect,
                outputRect: geometry.outputRect,
                scale: geometry.scale,
                canvasHeight: geometry.layout.canvasSize.height
            )
            if resizeHandle(for: previewRect).contains(viewPoint),
               let item = document.items.first(where: { $0.id == itemLayout.id }) {
                document.select(itemLayout.id)
                let center = NSPoint(x: itemLayout.imageRect.midX, y: itemLayout.imageRect.midY)
                dragMode = .resize(
                    id: itemLayout.id,
                    startPoint: layoutPoint,
                    startScale: item.scale,
                    center: center
                )
                onDocumentChanged?()
                return
            }
            if itemLayout.imageRect.contains(layoutPoint),
               let item = document.items.first(where: { $0.id == itemLayout.id }) {
                document.select(itemLayout.id)
                dragMode = .move(id: itemLayout.id, startPoint: layoutPoint, startOffset: item.offset)
                onDocumentChanged?()
                return
            }
        }

        document.select(nil)
        dragMode = nil
        onDocumentChanged?()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let document,
              let geometry = currentGeometry(),
              let dragMode
        else { return }

        let viewPoint = convert(event.locationInWindow, from: nil)
        let layoutPoint = ImageMergeRenderer.layoutPoint(
            from: viewPoint,
            outputRect: geometry.outputRect,
            scale: geometry.scale,
            canvasHeight: geometry.layout.canvasSize.height
        )

        switch dragMode {
        case .move(let id, let startPoint, let startOffset):
            let delta = NSPoint(x: layoutPoint.x - startPoint.x, y: layoutPoint.y - startPoint.y)
            updateSnappedMove(
                for: id,
                proposedOffset: NSPoint(x: startOffset.x + delta.x, y: startOffset.y + delta.y)
            )
        case .resize(let id, let startPoint, let startScale, let center):
            activeGuides.removeAll()
            let startDistance = max(12, hypot(startPoint.x - center.x, startPoint.y - center.y))
            let currentDistance = max(12, hypot(layoutPoint.x - center.x, layoutPoint.y - center.y))
            document.updateAdjustment(for: id, scale: startScale * currentDistance / startDistance)
        }

        onDocumentChanged?()
    }

    override func mouseUp(with event: NSEvent) {
        dragMode = nil
        activeGuides.removeAll()
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if deleteSelectedItemFromKeyboard(for: event) {
            return
        }
        super.keyDown(with: event)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggedFileURLs(from: sender).isEmpty ? [] : .copy
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        !draggedFileURLs(from: sender).isEmpty
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = draggedFileURLs(from: sender)
        guard !urls.isEmpty else { return false }
        onImportURLs?(urls)
        return true
    }

    private func currentGeometry() -> (layout: ImageMergeLayout, outputRect: NSRect, scale: CGFloat)? {
        guard let document else { return nil }
        return ImageMergeRenderer.previewGeometry(for: document, in: bounds.insetBy(dx: 28, dy: 28))
    }

    private func resizeHandle(for imageRect: NSRect) -> NSRect {
        NSRect(x: imageRect.maxX - 10, y: imageRect.minY - 10, width: 20, height: 20)
    }

    @discardableResult
    private func deleteSelectedItemFromKeyboard(for event: NSEvent) -> Bool {
        guard isImageMergeSelectionDeleteKey(event),
              let document,
              let selectedItemID = document.selectedItemID
        else {
            return false
        }

        document.removeItem(id: selectedItemID)
        dragMode = nil
        activeGuides.removeAll()
        needsDisplay = true
        onDocumentChanged?()
        return true
    }

    private func updateSnappedMove(for id: UUID, proposedOffset: NSPoint) {
        guard let document else { return }
        document.updateAdjustment(for: id, offset: proposedOffset)

        guard let geometry = currentGeometry() else {
            activeGuides.removeAll()
            return
        }

        let threshold = snapThreshold(for: geometry.scale)
        let snap = snapResult(for: id, in: geometry.layout, threshold: threshold)
        let snappedOffset = NSPoint(
            x: proposedOffset.x + snap.delta.x,
            y: proposedOffset.y + snap.delta.y
        )

        if abs(snap.delta.x) > 0.0001 || abs(snap.delta.y) > 0.0001 {
            document.updateAdjustment(for: id, offset: snappedOffset)
        }

        guard let finalGeometry = currentGeometry() else {
            activeGuides.removeAll()
            return
        }

        activeGuides = snapResult(
            for: id,
            in: finalGeometry.layout,
            threshold: snapThreshold(for: finalGeometry.scale)
        ).guides
    }

    private func snapThreshold(for scale: CGFloat) -> CGFloat {
        max(1, snapThresholdInScreenPoints / max(scale, 0.0001))
    }

    private func snapResult(
        for id: UUID,
        in layout: ImageMergeLayout,
        threshold: CGFloat
    ) -> (delta: NSPoint, guides: [SnapGuide]) {
        guard let draggedLayout = layout.itemLayouts.first(where: { $0.id == id }) else {
            return (.zero, [])
        }
        let dragged = draggedLayout.imageRect
        let references = layout.itemLayouts
            .filter { $0.id != id }
            .map(\.imageRect)
        var alignmentReferences = references
        alignmentReferences.append(draggedLayout.slotRect)
        if let slotBounds = unionRect(layout.itemLayouts.map(\.slotRect)) {
            alignmentReferences.append(slotBounds)
        }

        let xCandidate = bestHorizontalSnap(
            for: dragged,
            alignmentReferences: alignmentReferences,
            spacingReferences: references,
            threshold: threshold
        )
        var bestXCandidate = xCandidate
        if let canvasCenterXCandidate = canvasVerticalCenterSnap(
            for: dragged,
            canvasSize: layout.canvasSize,
            threshold: threshold
        ) {
            updateBestCandidate(&bestXCandidate, with: canvasCenterXCandidate)
        }

        let yCandidate = bestVerticalSnap(
            for: dragged,
            alignmentReferences: alignmentReferences,
            spacingReferences: references,
            threshold: threshold
        )
        var bestYCandidate = yCandidate
        if let canvasCenterYCandidate = canvasHorizontalCenterSnap(
            for: dragged,
            canvasSize: layout.canvasSize,
            threshold: threshold
        ) {
            updateBestCandidate(&bestYCandidate, with: canvasCenterYCandidate)
        }

        return (
            NSPoint(x: bestXCandidate?.delta ?? 0, y: bestYCandidate?.delta ?? 0),
            (bestXCandidate?.guides ?? []) + (bestYCandidate?.guides ?? [])
        )
    }

    private func bestHorizontalSnap(
        for dragged: NSRect,
        alignmentReferences: [NSRect],
        spacingReferences: [NSRect],
        threshold: CGFloat
    ) -> SnapAxisCandidate? {
        var best: SnapAxisCandidate?

        for reference in alignmentReferences {
            let anchorPairs: [(drag: CGFloat, ref: CGFloat, priority: Int)] = [
                (dragged.minX, reference.minX, 2),
                (dragged.midX, reference.midX, 3),
                (dragged.maxX, reference.maxX, 2)
            ]

            for pair in anchorPairs {
                let delta = pair.ref - pair.drag
                let distance = abs(delta)
                guard distance <= threshold else { continue }
                let candidate = SnapAxisCandidate(
                    delta: delta,
                    distance: distance,
                    priority: pair.priority,
                    guides: [
                        verticalGuide(
                            x: pair.ref,
                            spanning: dragged.offsetBy(dx: delta, dy: 0),
                            and: reference,
                            style: .alignment
                        )
                    ]
                )
                updateBestCandidate(&best, with: candidate)
            }
        }

        for candidate in horizontalSpacingCandidates(
            for: dragged,
            references: spacingReferences,
            threshold: threshold
        ) {
            updateBestCandidate(&best, with: candidate)
        }

        return best
    }

    private func bestVerticalSnap(
        for dragged: NSRect,
        alignmentReferences: [NSRect],
        spacingReferences: [NSRect],
        threshold: CGFloat
    ) -> SnapAxisCandidate? {
        var best: SnapAxisCandidate?

        for reference in alignmentReferences {
            let anchorPairs: [(drag: CGFloat, ref: CGFloat, priority: Int)] = [
                (dragged.minY, reference.minY, 2),
                (dragged.midY, reference.midY, 3),
                (dragged.maxY, reference.maxY, 2)
            ]

            for pair in anchorPairs {
                let delta = pair.ref - pair.drag
                let distance = abs(delta)
                guard distance <= threshold else { continue }
                let candidate = SnapAxisCandidate(
                    delta: delta,
                    distance: distance,
                    priority: pair.priority,
                    guides: [
                        horizontalGuide(
                            y: pair.ref,
                            spanning: dragged.offsetBy(dx: 0, dy: delta),
                            and: reference,
                            style: .alignment
                        )
                    ]
                )
                updateBestCandidate(&best, with: candidate)
            }
        }

        for candidate in verticalSpacingCandidates(
            for: dragged,
            references: spacingReferences,
            threshold: threshold
        ) {
            updateBestCandidate(&best, with: candidate)
        }

        return best
    }

    private func horizontalSpacingCandidates(
        for dragged: NSRect,
        references: [NSRect],
        threshold: CGFloat
    ) -> [SnapAxisCandidate] {
        let gaps = horizontalGapReferences(from: references)
        var candidates: [SnapAxisCandidate] = []

        for reference in references where overlapsVertically(dragged, reference) {
            for gapReference in gaps {
                if dragged.minX >= reference.maxX {
                    let currentGap = dragged.minX - reference.maxX
                    let delta = gapReference.gap - currentGap
                    if abs(delta) <= threshold {
                        let snapped = dragged.offsetBy(dx: delta, dy: 0)
                        candidates.append(
                            SnapAxisCandidate(
                                delta: delta,
                                distance: abs(delta),
                                priority: 1,
                                guides: [
                                    horizontalSpacingGuide(from: reference, to: snapped),
                                    horizontalSpacingGuide(from: gapReference.leading, to: gapReference.trailing)
                                ]
                            )
                        )
                    }
                }

                if dragged.maxX <= reference.minX {
                    let delta = reference.minX - gapReference.gap - dragged.maxX
                    if abs(delta) <= threshold {
                        let snapped = dragged.offsetBy(dx: delta, dy: 0)
                        candidates.append(
                            SnapAxisCandidate(
                                delta: delta,
                                distance: abs(delta),
                                priority: 1,
                                guides: [
                                    horizontalSpacingGuide(from: snapped, to: reference),
                                    horizontalSpacingGuide(from: gapReference.leading, to: gapReference.trailing)
                                ]
                            )
                        )
                    }
                }
            }
        }

        for left in references {
            for right in references where right.minX >= left.maxX {
                guard overlapsVertically(dragged, left) || overlapsVertically(dragged, right) else { continue }
                let available = right.minX - left.maxX - dragged.width
                guard available >= 0 else { continue }
                let equalGap = available / 2
                let desiredMinX = left.maxX + equalGap
                let delta = desiredMinX - dragged.minX
                guard abs(delta) <= threshold else { continue }
                let snapped = dragged.offsetBy(dx: delta, dy: 0)
                candidates.append(
                    SnapAxisCandidate(
                        delta: delta,
                        distance: abs(delta),
                        priority: 2,
                        guides: [
                            horizontalSpacingGuide(from: left, to: snapped),
                            horizontalSpacingGuide(from: snapped, to: right)
                        ]
                    )
                )
            }
        }

        return candidates
    }

    private func verticalSpacingCandidates(
        for dragged: NSRect,
        references: [NSRect],
        threshold: CGFloat
    ) -> [SnapAxisCandidate] {
        let gaps = verticalGapReferences(from: references)
        var candidates: [SnapAxisCandidate] = []

        for reference in references where overlapsHorizontally(dragged, reference) {
            for gapReference in gaps {
                if dragged.minY >= reference.maxY {
                    let currentGap = dragged.minY - reference.maxY
                    let delta = gapReference.gap - currentGap
                    if abs(delta) <= threshold {
                        let snapped = dragged.offsetBy(dx: 0, dy: delta)
                        candidates.append(
                            SnapAxisCandidate(
                                delta: delta,
                                distance: abs(delta),
                                priority: 1,
                                guides: [
                                    verticalSpacingGuide(from: reference, to: snapped),
                                    verticalSpacingGuide(from: gapReference.leading, to: gapReference.trailing)
                                ]
                            )
                        )
                    }
                }

                if dragged.maxY <= reference.minY {
                    let delta = reference.minY - gapReference.gap - dragged.maxY
                    if abs(delta) <= threshold {
                        let snapped = dragged.offsetBy(dx: 0, dy: delta)
                        candidates.append(
                            SnapAxisCandidate(
                                delta: delta,
                                distance: abs(delta),
                                priority: 1,
                                guides: [
                                    verticalSpacingGuide(from: snapped, to: reference),
                                    verticalSpacingGuide(from: gapReference.leading, to: gapReference.trailing)
                                ]
                            )
                        )
                    }
                }
            }
        }

        for top in references {
            for bottom in references where bottom.minY >= top.maxY {
                guard overlapsHorizontally(dragged, top) || overlapsHorizontally(dragged, bottom) else { continue }
                let available = bottom.minY - top.maxY - dragged.height
                guard available >= 0 else { continue }
                let equalGap = available / 2
                let desiredMinY = top.maxY + equalGap
                let delta = desiredMinY - dragged.minY
                guard abs(delta) <= threshold else { continue }
                let snapped = dragged.offsetBy(dx: 0, dy: delta)
                candidates.append(
                    SnapAxisCandidate(
                        delta: delta,
                        distance: abs(delta),
                        priority: 2,
                        guides: [
                            verticalSpacingGuide(from: top, to: snapped),
                            verticalSpacingGuide(from: snapped, to: bottom)
                        ]
                    )
                )
            }
        }

        return candidates
    }

    private func horizontalGapReferences(from references: [NSRect]) -> [GapReference] {
        var gaps: [GapReference] = []
        for left in references {
            for right in references where right.minX >= left.maxX {
                guard overlapsVertically(left, right) else { continue }
                let gap = right.minX - left.maxX
                guard gap >= 1 else { continue }
                gaps.append(GapReference(gap: gap, leading: left, trailing: right))
            }
        }
        return gaps
    }

    private func verticalGapReferences(from references: [NSRect]) -> [GapReference] {
        var gaps: [GapReference] = []
        for top in references {
            for bottom in references where bottom.minY >= top.maxY {
                guard overlapsHorizontally(top, bottom) else { continue }
                let gap = bottom.minY - top.maxY
                guard gap >= 1 else { continue }
                gaps.append(GapReference(gap: gap, leading: top, trailing: bottom))
            }
        }
        return gaps
    }

    private func canvasVerticalCenterSnap(
        for dragged: NSRect,
        canvasSize: NSSize,
        threshold: CGFloat
    ) -> SnapAxisCandidate? {
        let centerX = canvasSize.width / 2
        let delta = centerX - dragged.midX
        let distance = abs(delta)
        guard distance <= threshold else { return nil }
        return SnapAxisCandidate(
            delta: delta,
            distance: distance,
            priority: 4,
            guides: [
                SnapGuide(
                    start: NSPoint(x: centerX, y: 0),
                    end: NSPoint(x: centerX, y: canvasSize.height),
                    style: .alignment
                )
            ]
        )
    }

    private func canvasHorizontalCenterSnap(
        for dragged: NSRect,
        canvasSize: NSSize,
        threshold: CGFloat
    ) -> SnapAxisCandidate? {
        let centerY = canvasSize.height / 2
        let delta = centerY - dragged.midY
        let distance = abs(delta)
        guard distance <= threshold else { return nil }
        return SnapAxisCandidate(
            delta: delta,
            distance: distance,
            priority: 4,
            guides: [
                SnapGuide(
                    start: NSPoint(x: 0, y: centerY),
                    end: NSPoint(x: canvasSize.width, y: centerY),
                    style: .alignment
                )
            ]
        )
    }

    private func unionRect(_ rects: [NSRect]) -> NSRect? {
        guard var result = rects.first else { return nil }
        for rect in rects.dropFirst() {
            result = result.union(rect)
        }
        return result
    }

    private func updateBestCandidate(_ best: inout SnapAxisCandidate?, with candidate: SnapAxisCandidate) {
        guard let current = best else {
            best = candidate
            return
        }

        if candidate.distance < current.distance - 0.0001 {
            best = candidate
        } else if abs(candidate.distance - current.distance) <= 0.0001,
                  candidate.priority > current.priority {
            best = candidate
        }
    }

    private func verticalGuide(
        x: CGFloat,
        spanning first: NSRect,
        and second: NSRect,
        style: SnapGuideStyle
    ) -> SnapGuide {
        SnapGuide(
            start: NSPoint(x: x, y: min(first.minY, second.minY) - guideExtension),
            end: NSPoint(x: x, y: max(first.maxY, second.maxY) + guideExtension),
            style: style
        )
    }

    private func horizontalGuide(
        y: CGFloat,
        spanning first: NSRect,
        and second: NSRect,
        style: SnapGuideStyle
    ) -> SnapGuide {
        SnapGuide(
            start: NSPoint(x: min(first.minX, second.minX) - guideExtension, y: y),
            end: NSPoint(x: max(first.maxX, second.maxX) + guideExtension, y: y),
            style: style
        )
    }

    private func horizontalSpacingGuide(from first: NSRect, to second: NSRect) -> SnapGuide {
        let left = first.maxX <= second.minX ? first : second
        let right = first.maxX <= second.minX ? second : first
        let y = overlappingMidpoint(
            firstMin: left.minY,
            firstMax: left.maxY,
            secondMin: right.minY,
            secondMax: right.maxY,
            fallback: (left.midY + right.midY) / 2
        )
        return SnapGuide(
            start: NSPoint(x: left.maxX, y: y),
            end: NSPoint(x: right.minX, y: y),
            style: .spacing
        )
    }

    private func verticalSpacingGuide(from first: NSRect, to second: NSRect) -> SnapGuide {
        let top = first.maxY <= second.minY ? first : second
        let bottom = first.maxY <= second.minY ? second : first
        let x = overlappingMidpoint(
            firstMin: top.minX,
            firstMax: top.maxX,
            secondMin: bottom.minX,
            secondMax: bottom.maxX,
            fallback: (top.midX + bottom.midX) / 2
        )
        return SnapGuide(
            start: NSPoint(x: x, y: top.maxY),
            end: NSPoint(x: x, y: bottom.minY),
            style: .spacing
        )
    }

    private func overlappingMidpoint(
        firstMin: CGFloat,
        firstMax: CGFloat,
        secondMin: CGFloat,
        secondMax: CGFloat,
        fallback: CGFloat
    ) -> CGFloat {
        let minValue = max(firstMin, secondMin)
        let maxValue = min(firstMax, secondMax)
        guard maxValue > minValue else { return fallback }
        return (minValue + maxValue) / 2
    }

    private func overlapsVertically(_ first: NSRect, _ second: NSRect) -> Bool {
        min(first.maxY, second.maxY) - max(first.minY, second.minY) > 1
    }

    private func overlapsHorizontally(_ first: NSRect, _ second: NSRect) -> Bool {
        min(first.maxX, second.maxX) - max(first.minX, second.minX) > 1
    }

    private func drawGuides(
        _ guides: [SnapGuide],
        outputRect: NSRect,
        scale: CGFloat
    ) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        for guide in guides {
            let path = NSBezierPath()
            path.move(to: previewPoint(for: guide.start, outputRect: outputRect, scale: scale))
            path.line(to: previewPoint(for: guide.end, outputRect: outputRect, scale: scale))
            path.lineCapStyle = .round

            switch guide.style {
            case .alignment:
                NSColor.systemBlue.withAlphaComponent(0.9).setStroke()
                path.lineWidth = 1.5
                path.setLineDash([7, 4], count: 2, phase: 0)
            case .spacing:
                NSColor.systemOrange.withAlphaComponent(0.92).setStroke()
                path.lineWidth = 1.4
                path.setLineDash([3, 4], count: 2, phase: 0)
            }

            path.stroke()
        }
    }

    private func previewPoint(for layoutPoint: NSPoint, outputRect: NSRect, scale: CGFloat) -> NSPoint {
        NSPoint(
            x: outputRect.minX + layoutPoint.x * scale,
            y: outputRect.maxY - layoutPoint.y * scale
        )
    }

    private func drawCanvasSizeLabel(canvasSize: NSSize, near outputRect: NSRect) {
        let label = "\(Int(ceil(canvasSize.width))) x \(Int(ceil(canvasSize.height)))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.labelColor.withAlphaComponent(0.86)
        ]
        let textSize = label.size(withAttributes: attrs)
        let paddingX: CGFloat = 8
        let badgeHeight: CGFloat = 20
        let badgeRect = NSRect(
            x: outputRect.minX,
            y: min(outputRect.maxY + 8, bounds.maxY - badgeHeight - 6),
            width: ceil(textSize.width) + paddingX * 2,
            height: badgeHeight
        )

        NSColor.windowBackgroundColor.withAlphaComponent(0.92).setFill()
        NSBezierPath(roundedRect: badgeRect, xRadius: 5, yRadius: 5).fill()
        NSColor.separatorColor.withAlphaComponent(0.55).setStroke()
        let border = NSBezierPath(roundedRect: badgeRect.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5)
        border.lineWidth = 1
        border.stroke()

        label.draw(
            at: NSPoint(
                x: badgeRect.minX + paddingX,
                y: badgeRect.midY - textSize.height / 2
            ),
            withAttributes: attrs
        )
    }

    private func draggedFileURLs(from sender: NSDraggingInfo) -> [URL] {
        let pasteboard = sender.draggingPasteboard
        guard let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] else {
            return []
        }
        return urls
    }

    private func drawEmptyState() {
        let title = L10n.imageMergeEmptyTitle
        let body = L10n.imageMergeEmptyBody
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 22, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
        let bodyAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
        ]

        let titleSize = title.size(withAttributes: titleAttrs)
        let bodySize = body.size(withAttributes: bodyAttrs)
        let centerY = bounds.midY + 18

        title.draw(
            at: NSPoint(x: bounds.midX - titleSize.width / 2, y: centerY),
            withAttributes: titleAttrs
        )
        body.draw(
            at: NSPoint(x: bounds.midX - bodySize.width / 2, y: centerY - 30),
            withAttributes: bodyAttrs
        )
    }
}

final class ImageMergeThumbnailListView: NSView {
    var document: ImageMergeDocument? {
        didSet {
            if let rowDragState,
               document?.items.contains(where: { $0.id == rowDragState.id }) != true {
                self.rowDragState = nil
                stopAutoScroll()
            }
            rebuildHeight()
        }
    }
    var onReorder: (() -> Void)?
    var onSelect: (() -> Void)?
    var onDelete: (() -> Void)?

    private struct RowDragState {
        let id: UUID
        let sourceIndex: Int
        let startY: CGFloat
        let grabOffsetY: CGFloat
        var currentY: CGFloat
        var dropIndex: Int
        var isActive: Bool
    }

    private var rowRects: [UUID: NSRect] = [:]
    private var closeRects: [UUID: NSRect] = [:]
    private var rowDragState: RowDragState?
    private var autoScrollTimer: Timer?
    private let rowHeight: CGFloat = 58
    private let dragActivationDistance: CGFloat = 3
    private let draggedRowScale: CGFloat = 0.965
    private let autoScrollEdgeInset: CGFloat = 28
    private let maxAutoScrollStep: CGFloat = 12

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            stopAutoScroll()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        bounds.fill()
        rowRects.removeAll()
        closeRects.removeAll()

        guard let document else { return }
        if let rowDragState, rowDragState.isActive {
            drawDraggingRows(document: document, dragState: rowDragState)
            return
        }

        for (index, item) in document.items.enumerated() {
            let rect = rowRect(for: index)
            rowRects[item.id] = rect
            drawRow(item: item, index: index, in: rect, selected: item.id == document.selectedItemID)
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let document else { return }
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)

        for item in document.items {
            if closeRects[item.id]?.contains(point) == true {
                document.removeItem(id: item.id)
                rowDragState = nil
                rebuildHeight()
                needsDisplay = true
                onDelete?()
                return
            }
        }

        for (index, item) in document.items.enumerated() {
            if rowRects[item.id]?.contains(point) == true {
                document.select(item.id)
                let rowRect = rowRects[item.id] ?? rowRect(for: index)
                rowDragState = RowDragState(
                    id: item.id,
                    sourceIndex: index,
                    startY: point.y,
                    grabOffsetY: point.y - rowRect.minY,
                    currentY: point.y,
                    dropIndex: index,
                    isActive: false
                )
                needsDisplay = true
                onSelect?()
                return
            }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let document, var dragState = rowDragState else { return }
        let point = convert(event.locationInWindow, from: nil)
        dragState.currentY = point.y
        if !dragState.isActive, abs(point.y - dragState.startY) >= dragActivationDistance {
            dragState.isActive = true
        }
        if dragState.isActive {
            dragState.dropIndex = dropIndex(for: dragState, itemCount: document.items.count)
        }
        rowDragState = dragState
        updateAutoScrollState()
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let dragState = rowDragState else { return }
        rowDragState = nil
        stopAutoScroll()

        if dragState.isActive, dragState.sourceIndex != dragState.dropIndex {
            document?.reorderItem(from: dragState.sourceIndex, to: dragState.dropIndex)
            onReorder?()
        }
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if deleteSelectedItemFromKeyboard(for: event) {
            return
        }
        super.keyDown(with: event)
    }

    private func rebuildHeight() {
        let count = max(2, document?.items.count ?? 0)
        setFrameSize(NSSize(width: frame.width, height: CGFloat(count) * rowHeight))
        needsDisplay = true
    }

    @discardableResult
    private func deleteSelectedItemFromKeyboard(for event: NSEvent) -> Bool {
        guard isImageMergeSelectionDeleteKey(event),
              let document,
              let selectedItemID = document.selectedItemID
        else {
            return false
        }

        document.removeItem(id: selectedItemID)
        rowDragState = nil
        stopAutoScroll()
        rebuildHeight()
        needsDisplay = true
        onDelete?()
        return true
    }

    private func rowRect(for index: Int) -> NSRect {
        let y = bounds.height - CGFloat(index + 1) * rowHeight
        return NSRect(x: 0, y: y, width: bounds.width, height: rowHeight - 6)
    }

    private func dropIndex(for dragState: RowDragState, itemCount: Int) -> Int {
        guard itemCount > 0 else { return 0 }
        let draggedMidY = draggedRowRect(for: dragState).midY
        let index = Int(round((bounds.height - draggedMidY - rowHeight / 2) / rowHeight))
        return min(max(index, 0), itemCount - 1)
    }

    private func draggedRowRect(for dragState: RowDragState) -> NSRect {
        let unclampedY = dragState.currentY - dragState.grabOffsetY
        let maxY = max(0, bounds.height - rowHeight)
        let y = min(max(unclampedY, 0), maxY)
        return NSRect(x: 0, y: y, width: bounds.width, height: rowHeight - 6)
    }

    private func updateAutoScrollState() {
        guard rowDragState?.isActive == true,
              autoScrollDelta() != 0
        else {
            stopAutoScroll()
            return
        }

        guard autoScrollTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.performAutoScrollTick()
        }
        RunLoop.main.add(timer, forMode: .common)
        autoScrollTimer = timer
    }

    private func stopAutoScroll() {
        autoScrollTimer?.invalidate()
        autoScrollTimer = nil
    }

    private func performAutoScrollTick() {
        guard let document,
              var dragState = rowDragState,
              dragState.isActive,
              let scrollView = enclosingScrollView
        else {
            stopAutoScroll()
            return
        }

        let delta = autoScrollDelta()
        guard delta != 0 else {
            stopAutoScroll()
            return
        }

        let clipView = scrollView.contentView
        let visible = clipView.bounds
        let maxOriginY = max(0, bounds.height - visible.height)
        let proposedY = min(max(visible.origin.y + delta, 0), maxOriginY)
        guard abs(proposedY - visible.origin.y) > 0.0001 else {
            stopAutoScroll()
            return
        }

        clipView.scroll(to: NSPoint(x: visible.origin.x, y: proposedY))
        scrollView.reflectScrolledClipView(clipView)

        let point = currentMousePoint()
        dragState.currentY = point.y
        dragState.dropIndex = dropIndex(for: dragState, itemCount: document.items.count)
        rowDragState = dragState
        needsDisplay = true
    }

    private func autoScrollDelta() -> CGFloat {
        guard rowDragState?.isActive == true,
              enclosingScrollView != nil
        else { return 0 }

        let point = currentMousePoint()
        let visible = visibleRect
        let topDistance = visible.maxY - point.y
        if topDistance < autoScrollEdgeInset {
            return scaledAutoScrollStep(for: autoScrollEdgeInset - max(topDistance, 0))
        }

        let bottomDistance = point.y - visible.minY
        if bottomDistance < autoScrollEdgeInset {
            return -scaledAutoScrollStep(for: autoScrollEdgeInset - max(bottomDistance, 0))
        }

        return 0
    }

    private func scaledAutoScrollStep(for edgeDepth: CGFloat) -> CGFloat {
        let progress = min(max(edgeDepth / autoScrollEdgeInset, 0), 1)
        return max(2, maxAutoScrollStep * progress)
    }

    private func currentMousePoint() -> NSPoint {
        guard let window else { return rowDragState.map { NSPoint(x: bounds.midX, y: $0.currentY) } ?? .zero }
        return convert(window.mouseLocationOutsideOfEventStream, from: nil)
    }

    private func drawDraggingRows(document: ImageMergeDocument, dragState: RowDragState) {
        guard let draggedItem = document.items.first(where: { $0.id == dragState.id }) else { return }
        var remainingItems = document.items.filter { $0.id != dragState.id }

        for visualIndex in 0..<document.items.count {
            let rect = rowRect(for: visualIndex)
            if visualIndex == dragState.dropIndex {
                drawDropPlaceholder(item: draggedItem, index: visualIndex, in: rect)
            } else if !remainingItems.isEmpty {
                let item = remainingItems.removeFirst()
                rowRects[item.id] = rect
                drawRow(item: item, index: visualIndex, in: rect, selected: item.id == document.selectedItemID)
            }
        }

        drawDraggedRow(
            item: draggedItem,
            index: dragState.dropIndex,
            in: draggedRowRect(for: dragState)
        )
    }

    private func drawRow(
        item: ImageMergeItem,
        index: Int,
        in rect: NSRect,
        selected: Bool,
        alpha: CGFloat = 1,
        showsCloseButton: Bool = true
    ) {
        guard let cgContext = NSGraphicsContext.current?.cgContext else { return }
        cgContext.saveGState()
        cgContext.setAlpha(alpha)
        defer { cgContext.restoreGState() }

        let path = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 8, yRadius: 8)
        (selected ? NSColor.controlAccentColor.withAlphaComponent(0.16) : NSColor.controlBackgroundColor).setFill()
        path.fill()
        (selected ? NSColor.controlAccentColor.withAlphaComponent(0.8) : NSColor.separatorColor).setStroke()
        path.lineWidth = selected ? 1.5 : 1
        path.stroke()

        let closeRect = NSRect(
            x: rect.maxX - 34,
            y: rect.midY - 11,
            width: 22,
            height: 22
        )
        if showsCloseButton {
            closeRects[item.id] = closeRect
        }

        let handleRect = NSRect(x: rect.minX + 8, y: rect.midY - 14, width: 14, height: 28)
        drawDragHandle(in: handleRect, selected: selected)

        let thumbRect = NSRect(x: handleRect.maxX + 8, y: rect.minY + 7, width: 44, height: 44)
        NSColor(calibratedWhite: 0.15, alpha: 0.12).setFill()
        NSBezierPath(roundedRect: thumbRect, xRadius: 5, yRadius: 5).fill()
        drawThumbnail(item.image, in: thumbRect.insetBy(dx: 3, dy: 3))

        let title = "\(index + 1). \(item.displayName)"
        let titleParagraph = NSMutableParagraphStyle()
        titleParagraph.lineBreakMode = .byTruncatingMiddle
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: titleParagraph
        ]
        let metadataParagraph = NSMutableParagraphStyle()
        metadataParagraph.lineBreakMode = .byTruncatingTail
        let metadataAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: metadataParagraph
        ]
        let textX = thumbRect.maxX + 8
        let textWidth = max(20, closeRect.minX - thumbRect.maxX - 18)
        title.draw(
            in: NSRect(x: textX, y: rect.midY + 3, width: textWidth, height: 16),
            withAttributes: titleAttrs
        )
        itemSizeText(for: item).draw(
            in: NSRect(x: textX, y: rect.midY - 13, width: textWidth, height: 14),
            withAttributes: metadataAttrs
        )
        if showsCloseButton {
            drawCloseButton(in: closeRect)
        }
    }

    private func drawDropPlaceholder(item: ImageMergeItem, index: Int, in rect: NSRect) {
        let path = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 8, yRadius: 8)
        NSColor.controlAccentColor.withAlphaComponent(0.08).setFill()
        path.fill()
        NSColor.controlAccentColor.withAlphaComponent(0.35).setStroke()
        path.lineWidth = 1.5
        path.setLineDash([6, 4], count: 2, phase: 0)
        path.stroke()

        drawRow(
            item: item,
            index: index,
            in: rect,
            selected: false,
            alpha: 0.24,
            showsCloseButton: false
        )
    }

    private func drawDraggedRow(item: ImageMergeItem, index: Int, in rect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.24)
        shadow.shadowBlurRadius = 10
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.set()

        let transform = NSAffineTransform()
        transform.translateX(by: rect.midX, yBy: rect.midY)
        transform.scale(by: draggedRowScale)
        transform.translateX(by: -rect.midX, yBy: -rect.midY)
        transform.concat()

        rowRects[item.id] = rect
        drawRow(item: item, index: index, in: rect, selected: true)
    }

    private func itemSizeText(for item: ImageMergeItem) -> String {
        let width = Int(round(item.originalSize.width))
        let height = Int(round(item.originalSize.height))
        return "\(width) x \(height)"
    }

    private func drawDragHandle(in rect: NSRect, selected: Bool) {
        let color = selected
            ? NSColor.controlAccentColor.withAlphaComponent(0.82)
            : NSColor.labelColor.withAlphaComponent(0.36)
        color.setFill()

        let dotSize: CGFloat = 3.4
        let columnSpacing: CGFloat = 7
        let rowSpacing: CGFloat = 8
        let startX = rect.midX - columnSpacing / 2 - dotSize / 2
        let startY = rect.midY - rowSpacing - dotSize / 2

        for column in 0..<2 {
            for row in 0..<3 {
                let dot = NSRect(
                    x: startX + CGFloat(column) * columnSpacing,
                    y: startY + CGFloat(row) * rowSpacing,
                    width: dotSize,
                    height: dotSize
                )
                NSBezierPath(ovalIn: dot).fill()
            }
        }
    }

    private func drawThumbnail(_ image: NSImage, in rect: NSRect) {
        guard image.size.width > 0, image.size.height > 0 else { return }
        let scale = min(rect.width / image.size.width, rect.height / image.size.height)
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        let target = NSRect(
            x: rect.midX - size.width / 2,
            y: rect.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        image.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1)
    }

    private func drawCloseButton(in rect: NSRect) {
        let circle = NSBezierPath(ovalIn: rect)
        NSColor.labelColor.withAlphaComponent(0.10).setFill()
        circle.fill()

        let lineWidth: CGFloat = 1.8
        let inset = rect.insetBy(dx: 6.5, dy: 6.5)
        let path = NSBezierPath()
        path.move(to: NSPoint(x: inset.minX, y: inset.minY))
        path.line(to: NSPoint(x: inset.maxX, y: inset.maxY))
        path.move(to: NSPoint(x: inset.maxX, y: inset.minY))
        path.line(to: NSPoint(x: inset.minX, y: inset.maxY))
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        NSColor.labelColor.withAlphaComponent(0.64).setStroke()
        path.stroke()
    }
}
