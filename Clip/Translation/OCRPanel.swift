import AVFoundation
import AppKit
import CoreText
import VisionKit

// MARK: - Shared helpers

/// capcap is an LSUIElement app with no main menu, so Cmd+C/V/X/A never reach
/// the field editor on their own. Route them through the responder chain.
func dispatchEditingShortcut(_ event: NSEvent) -> Bool {
    guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command else {
        return false
    }
    let action: Selector
    switch event.charactersIgnoringModifiers {
    case "x": action = #selector(NSText.cut(_:))
    case "c": action = #selector(NSText.copy(_:))
    case "v": action = #selector(NSText.paste(_:))
    case "a": action = #selector(NSText.selectAll(_:))
    default: return false
    }
    return NSApp.sendAction(action, to: nil, from: nil)
}

/// NSTextView that honors copy/paste shortcuts without a menu.
final class PanelTextView: NSTextView {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if dispatchEditingShortcut(event) { return true }
        return super.performKeyEquivalent(with: event)
    }
}

/// Top-aligned content host for the scroll view's document.
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

// MARK: - OCR image preview

final class OCRPreviewView: NSView, ImageAnalysisOverlayViewDelegate {
    private let image: NSImage
    private let imageView = NSImageView()
    private let lineOverlay: OCRLineSelectionOverlayView
    private var liveTextOverlay: ImageAnalysisOverlayView?

    var showsLineBoxes = false {
        didSet { updateOverlayVisibility() }
    }
    var lines: [RecognizedTextLine] = [] {
        didSet {
            lineOverlay.lines = lines
            updateOverlayVisibility()
        }
    }
    var onSelectText: ((String, [Int], Bool) -> Void)? {
        didSet { lineOverlay.onSelectText = onSelectText }
    }
    var onLiveTextMenuVisibilityChange: ((Bool) -> Void)?

    init(image: NSImage, showsChrome: Bool = true) {
        self.image = image
        self.lineOverlay = OCRLineSelectionOverlayView(imageSize: image.size)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = showsChrome ? 8 : 0
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.backgroundColor = showsChrome ? NSColor.black.withAlphaComponent(0.26).cgColor : nil
        layer?.borderWidth = showsChrome ? 1 : 0
        applyAppearance()

        imageView.image = image
        imageView.imageAlignment = .alignCenter
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.autoresizingMask = []
        addSubview(imageView)

        lineOverlay.autoresizingMask = [.width, .height]
        lineOverlay.isHidden = true
        imageView.addSubview(lineOverlay)

        if ImageAnalyzer.isSupported {
            let overlay = ImageAnalysisOverlayView()
            overlay.delegate = self
            overlay.preferredInteractionTypes = .automaticTextOnly
            overlay.selectableItemsHighlighted = true
            overlay.trackingImageView = imageView
            overlay.autoresizingMask = [.width, .height]
            overlay.isHidden = true
            imageView.addSubview(overlay)
            liveTextOverlay = overlay
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyAppearance()
    }

    private func applyAppearance() {
        layer?.borderColor = AdaptiveChrome.resolvedCGColor(
            AdaptiveChrome.border,
            for: effectiveAppearance
        )
    }

    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func layout() {
        super.layout()
        let imageRect = fittedImageRect()
        imageView.frame = imageRect
        lineOverlay.frame = imageView.bounds
        liveTextOverlay?.frame = imageView.bounds
        liveTextOverlay?.trackingImageView = imageView
        lineOverlay.needsDisplay = true
        liveTextOverlay?.setContentsRectNeedsUpdate()
    }

    func applyLiveTextAnalysis(_ analysis: ImageAnalysis?) {
        layoutSubtreeIfNeeded()
        liveTextOverlay?.analysis = analysis
        updateOverlayVisibility()
        liveTextOverlay?.setContentsRectNeedsUpdate()
    }

    var hasActiveLiveTextSelection: Bool {
        liveTextOverlay?.hasActiveTextSelection == true
    }

    func copySelectedLiveTextToClipboard() -> Bool {
        guard let selectedText = liveTextOverlay?.selectedText,
              !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(selectedText, forType: .string)
        return true
    }

    func copySelectedOverlayTextToClipboard() -> Bool {
        lineOverlay.copySelectedTextToClipboard()
    }

    func clearTextSelection() {
        lineOverlay.clearSelection()
        liveTextOverlay?.selectedRanges = []
    }

    func selectAllLiveText() -> Bool {
        guard let liveTextOverlay,
              !liveTextOverlay.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        let text = liveTextOverlay.text
        liveTextOverlay.selectedRanges = [text.startIndex..<text.endIndex]
        window?.makeFirstResponder(liveTextOverlay)
        return true
    }

    func selectAllOverlayText() -> Bool {
        lineOverlay.selectAllText()
    }

    private func updateOverlayVisibility() {
        let hasLiveText = liveTextOverlay?.analysis != nil
        let showFallbackLines = showsLineBoxes && !lines.isEmpty
        lineOverlay.showsLineBoxes = showFallbackLines
        lineOverlay.isHidden = !showFallbackLines
        liveTextOverlay?.isHidden = showFallbackLines || !hasLiveText
    }

    private func fittedImageRect() -> NSRect {
        guard image.size.width > 0, image.size.height > 0,
              bounds.width > 0, bounds.height > 0 else {
            return bounds
        }
        let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        return NSRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    func overlayView(
        _ overlayView: ImageAnalysisOverlayView,
        shouldBeginAt point: CGPoint,
        forAnalysisType analysisType: ImageAnalysisOverlayView.InteractionTypes
    ) -> Bool {
        true
    }

    func contentsRect(for overlayView: ImageAnalysisOverlayView) -> CGRect {
        imageView.bounds
    }

    func contentView(for overlayView: ImageAnalysisOverlayView) -> NSView? {
        imageView
    }

    func overlayView(_ overlayView: ImageAnalysisOverlayView, shouldHandleKeyDownEvent event: NSEvent) -> Bool {
        true
    }

    func overlayView(
        _ overlayView: ImageAnalysisOverlayView,
        shouldShowMenuForEvent event: NSEvent,
        atPoint point: CGPoint
    ) -> Bool {
        true
    }

    func overlayView(_ overlayView: ImageAnalysisOverlayView, liveTextButtonDidChangeToVisible visible: Bool) {}

    func overlayView(
        _ overlayView: ImageAnalysisOverlayView,
        highlightSelectedItemsDidChange highlightSelectedItems: Bool
    ) {}

    func textSelectionDidChange(_ overlayView: ImageAnalysisOverlayView) {}

    func overlayView(
        _ overlayView: ImageAnalysisOverlayView,
        updatedMenuFor menu: NSMenu,
        for event: NSEvent,
        at point: CGPoint
    ) -> NSMenu {
        menu
    }

    func overlayView(_ overlayView: ImageAnalysisOverlayView, needsUpdate menu: NSMenu) {}

    func overlayView(_ overlayView: ImageAnalysisOverlayView, willOpen menu: NSMenu) {
        onLiveTextMenuVisibilityChange?(true)
    }

    func overlayView(_ overlayView: ImageAnalysisOverlayView, didClose menu: NSMenu) {
        onLiveTextMenuVisibilityChange?(false)
    }

    func overlayView(
        _ overlayView: ImageAnalysisOverlayView,
        menu: NSMenu,
        willHighlight menuItem: NSMenuItem?
    ) {}
}

final class OCRLineSelectionOverlayView: NSView {
    private struct TokenRef: Hashable {
        let lineIndex: Int
        let tokenIndex: Int
    }

    private let imageSize: NSSize
    var showsLineBoxes = false {
        didSet {
            if !showsLineBoxes {
                clearSelection()
            }
            needsDisplay = true
        }
    }
    var lines: [RecognizedTextLine] = [] {
        didSet {
            selectedTokenRefs = Set(selectedTokenRefs.filter { ref in
                lines.indices.contains(ref.lineIndex)
                    && lines[ref.lineIndex].tokens.indices.contains(ref.tokenIndex)
            })
            selectedLineIndices = Set(selectedLineIndices.filter { lines.indices.contains($0) })
            selectedText = selectedText(for: orderedSelectedTokenRefs())
            needsDisplay = true
        }
    }
    var onSelectText: ((String, [Int], Bool) -> Void)?

    private var selectedTokenRefs: Set<TokenRef> = [] {
        didSet {
            if oldValue != selectedTokenRefs {
                needsDisplay = true
            }
        }
    }
    private var selectedLineIndices: Set<Int> = []
    private var selectedText = ""
    private var selectionStartPoint: NSPoint?
    private var selectionStartTokenRef: TokenRef?
    private var selectionStartLineIndex: Int?

    init(imageSize: NSSize) {
        self.imageSize = imageSize
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard showsLineBoxes else { return }

        let imageRect = fittedImageRect()
        let copyableRects = lines.enumerated().flatMap { index, line in
            textBlockRects(for: index, line: line, in: imageRect)
        }
        guard !copyableRects.isEmpty else { return }

        drawDimMask(excluding: copyableRects)
        drawCopyableTextBackplates(copyableRects)

        for rect in selectedTextRects(in: imageRect) {
            drawSelectedTextRect(rect)
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard showsLineBoxes, !lines.isEmpty else { return }
        let point = convert(event.locationInWindow, from: nil)
        let imageRect = fittedImageRect()
        selectionStartPoint = point
        selectionStartTokenRef = tokenRef(at: point, in: imageRect)
        selectionStartLineIndex = selectionStartTokenRef == nil ? lineIndex(at: point, in: imageRect) : nil
        updateSelection(to: point, isFinal: false)
    }

    override func mouseDragged(with event: NSEvent) {
        guard selectionStartPoint != nil else { return }
        let point = convert(event.locationInWindow, from: nil)
        updateSelection(to: point, isFinal: false)
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            selectionStartPoint = nil
            selectionStartTokenRef = nil
            selectionStartLineIndex = nil
        }
        guard selectionStartPoint != nil else { return }
        let point = convert(event.locationInWindow, from: nil)
        updateSelection(to: point, isFinal: true)
    }

    func copySelectedTextToClipboard() -> Bool {
        let trimmed = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(trimmed, forType: .string)
        return true
    }

    func selectAllText() -> Bool {
        let tokenRefs = lines.indices.flatMap { lineIndex in
            lines[lineIndex].tokens.indices.map { TokenRef(lineIndex: lineIndex, tokenIndex: $0) }
        }

        if tokenRefs.isEmpty {
            let lineIndices = Array(lines.indices)
            guard !lineIndices.isEmpty else { return false }
            selectedTokenRefs = []
            selectedLineIndices = Set(lineIndices)
            selectedText = lineIndices.map { lines[$0].text }.joined(separator: "\n")
            onSelectText?(selectedText, lineIndices, false)
        } else {
            selectedTokenRefs = Set(tokenRefs)
            selectedLineIndices = Set(tokenRefs.map(\.lineIndex))
            selectedText = selectedText(for: tokenRefs)
            onSelectText?(selectedText, Array(selectedLineIndices).sorted(), false)
        }
        needsDisplay = true
        return !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func fittedImageRect() -> NSRect {
        guard imageSize.width > 0, imageSize.height > 0,
              bounds.width > 0, bounds.height > 0 else {
            return bounds
        }
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let size = NSSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return NSRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private func displayRect(for normalizedRect: CGRect, in imageRect: NSRect) -> NSRect {
        NSRect(
            x: imageRect.minX + normalizedRect.minX * imageRect.width,
            y: imageRect.minY + normalizedRect.minY * imageRect.height,
            width: normalizedRect.width * imageRect.width,
            height: normalizedRect.height * imageRect.height
        )
    }

    private func updateSelection(to point: NSPoint, isFinal: Bool) {
        guard let start = selectionStartPoint else { return }
        if hasTokenBoxes {
            let refs = selectionTokenRefs(from: start, to: point, startTokenRef: selectionStartTokenRef)
            selectedTokenRefs = Set(refs)
            selectedLineIndices = Set(refs.map(\.lineIndex))
            selectedText = selectedText(for: refs)
        } else {
            let indices = selectionIndices(from: start, to: point, startLineIndex: selectionStartLineIndex)
            selectedTokenRefs = []
            selectedLineIndices = Set(indices)
            selectedText = indices
                .compactMap { lines.indices.contains($0) ? lines[$0].text : nil }
                .joined(separator: "\n")
        }
        onSelectText?(selectedText, Array(selectedLineIndices).sorted(), isFinal)
    }

    private var hasTokenBoxes: Bool {
        lines.contains { !$0.tokens.isEmpty }
    }

    func clearSelection() {
        selectedTokenRefs.removeAll()
        selectedLineIndices.removeAll()
        selectedText = ""
        selectionStartPoint = nil
        selectionStartTokenRef = nil
        selectionStartLineIndex = nil
        needsDisplay = true
    }

    private func selectionIndices(
        from start: NSPoint,
        to current: NSPoint,
        startLineIndex: Int?
    ) -> [Int] {
        let imageRect = fittedImageRect()
        if let startLineIndex {
            let targetIndex = lineIndex(at: current, in: imageRect)
                ?? nearestLineIndex(to: current, in: imageRect)
            guard let targetIndex else { return [startLineIndex] }
            return contiguousIndices(from: startLineIndex, to: targetIndex)
        }

        let rect = NSRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        ).insetBy(dx: -5, dy: -5)
        let hits = lines.indices.filter { index in
            lineHitRect(at: index, in: imageRect).intersects(rect)
        }
        return contiguousIndices(covering: hits)
    }

    private func selectionTokenRefs(
        from start: NSPoint,
        to current: NSPoint,
        startTokenRef: TokenRef?
    ) -> [TokenRef] {
        let imageRect = fittedImageRect()
        if let startTokenRef {
            let target = tokenRef(at: current, in: imageRect)
                ?? nearestTokenRef(to: current, in: imageRect)
            guard let target else { return [startTokenRef] }
            return contiguousTokenRefs(from: startTokenRef, to: target)
        }

        let rect = NSRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        ).insetBy(dx: -4, dy: -4)

        return orderedTokenRefs().filter { ref in
            tokenHitRect(ref, in: imageRect).intersects(rect)
        }
    }

    private func lineIndex(at point: NSPoint, in imageRect: NSRect) -> Int? {
        for index in lines.indices.reversed() {
            if lineHitRect(at: index, in: imageRect).contains(point) {
                return index
            }
        }
        return nil
    }

    private func nearestLineIndex(to point: NSPoint, in imageRect: NSRect) -> Int? {
        lines.indices.min { lhs, rhs in
            let leftDistance = distance(from: point, to: lineHitRect(at: lhs, in: imageRect))
            let rightDistance = distance(from: point, to: lineHitRect(at: rhs, in: imageRect))
            return leftDistance < rightDistance
        }
    }

    private func lineHitRect(at index: Int, in imageRect: NSRect) -> NSRect {
        displayRect(for: lines[index].boundingBox, in: imageRect).insetBy(dx: -4, dy: -3)
    }

    private func tokenRef(at point: NSPoint, in imageRect: NSRect) -> TokenRef? {
        for ref in orderedTokenRefs().reversed() where tokenHitRect(ref, in: imageRect).contains(point) {
            return ref
        }
        return nil
    }

    private func nearestTokenRef(to point: NSPoint, in imageRect: NSRect) -> TokenRef? {
        orderedTokenRefs().min { lhs, rhs in
            let leftDistance = distance(from: point, to: tokenHitRect(lhs, in: imageRect))
            let rightDistance = distance(from: point, to: tokenHitRect(rhs, in: imageRect))
            return leftDistance < rightDistance
        }
    }

    private func tokenHitRect(_ ref: TokenRef, in imageRect: NSRect) -> NSRect {
        tokenDisplayRect(ref, in: imageRect).insetBy(dx: -2, dy: -2)
    }

    private func tokenDisplayRect(_ ref: TokenRef, in imageRect: NSRect) -> NSRect {
        guard lines.indices.contains(ref.lineIndex),
              lines[ref.lineIndex].tokens.indices.contains(ref.tokenIndex) else {
            return .zero
        }
        return displayRect(for: lines[ref.lineIndex].tokens[ref.tokenIndex].boundingBox, in: imageRect)
    }

    private func distance(from point: NSPoint, to rect: NSRect) -> CGFloat {
        let dx: CGFloat
        if point.x < rect.minX {
            dx = rect.minX - point.x
        } else if point.x > rect.maxX {
            dx = point.x - rect.maxX
        } else {
            dx = 0
        }

        let dy: CGFloat
        if point.y < rect.minY {
            dy = rect.minY - point.y
        } else if point.y > rect.maxY {
            dy = point.y - rect.maxY
        } else {
            dy = 0
        }

        return hypot(dx, dy)
    }

    private func contiguousIndices(from start: Int, to end: Int) -> [Int] {
        guard lines.indices.contains(start), lines.indices.contains(end) else { return [] }
        return Array(min(start, end)...max(start, end))
    }

    private func contiguousIndices(covering indices: [Int]) -> [Int] {
        guard let first = indices.min(), let last = indices.max() else { return [] }
        return contiguousIndices(from: first, to: last)
    }

    private func orderedTokenRefs() -> [TokenRef] {
        lines.indices.flatMap { lineIndex in
            lines[lineIndex].tokens.indices.map { TokenRef(lineIndex: lineIndex, tokenIndex: $0) }
        }
    }

    private func orderedSelectedTokenRefs() -> [TokenRef] {
        orderedTokenRefs().filter { selectedTokenRefs.contains($0) }
    }

    private func contiguousTokenRefs(from start: TokenRef, to end: TokenRef) -> [TokenRef] {
        let ordered = orderedTokenRefs()
        guard let startIndex = ordered.firstIndex(of: start),
              let endIndex = ordered.firstIndex(of: end) else {
            return []
        }
        return Array(ordered[min(startIndex, endIndex)...max(startIndex, endIndex)])
    }

    private func selectedText(for refs: [TokenRef]) -> String {
        let grouped = Dictionary(grouping: refs, by: \.lineIndex)
        return grouped.keys.sorted().compactMap { lineIndex in
            guard lines.indices.contains(lineIndex),
                  let refs = grouped[lineIndex] else {
                return nil
            }
            let tokens = refs.sorted { $0.tokenIndex < $1.tokenIndex }.compactMap { ref -> String? in
                guard lines[lineIndex].tokens.indices.contains(ref.tokenIndex) else { return nil }
                return lines[lineIndex].tokens[ref.tokenIndex].text
            }
            return joinTokenTexts(tokens)
        }
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
    }

    private func joinTokenTexts(_ tokens: [String]) -> String {
        tokens.reduce(into: "") { result, token in
            guard !token.isEmpty else { return }
            if let previous = result.last,
               let first = token.first,
               shouldInsertSpace(between: previous, and: first) {
                result.append(" ")
            }
            result.append(token)
        }
    }

    private func shouldInsertSpace(between previous: Character, and next: Character) -> Bool {
        if previous.isCJKLike || next.isCJKLike { return false }
        if "([{<“‘\"".contains(previous) { return false }
        if ".,;:!?)]}>，。！？、；：”’\"".contains(next) { return false }
        return true
    }

    private func textBlockRects(
        for lineIndex: Int,
        line: RecognizedTextLine,
        in imageRect: NSRect
    ) -> [NSRect] {
        guard !line.tokens.isEmpty else {
            return [lineHitRect(at: lineIndex, in: imageRect).insetBy(dx: -3, dy: -2)]
        }

        let rects = line.tokens.indices.map {
            tokenDisplayRect(TokenRef(lineIndex: lineIndex, tokenIndex: $0), in: imageRect)
                .insetBy(dx: -3, dy: -2)
        }
        return mergedInlineRects(rects)
    }

    private func selectedTextRects(in imageRect: NSRect) -> [NSRect] {
        if selectedTokenRefs.isEmpty {
            return selectedLineIndices.sorted().compactMap { lineIndex in
                guard lines.indices.contains(lineIndex) else { return nil }
                return lineHitRect(at: lineIndex, in: imageRect).insetBy(dx: -3, dy: -2)
            }
        }

        let grouped = Dictionary(grouping: orderedSelectedTokenRefs(), by: \.lineIndex)
        return grouped.keys.sorted().flatMap { lineIndex in
            guard let refs = grouped[lineIndex] else { return [NSRect]() }
            let rects = refs.sorted { $0.tokenIndex < $1.tokenIndex }.map {
                tokenDisplayRect($0, in: imageRect).insetBy(dx: -2, dy: -1)
            }
            return mergedInlineRects(rects, maxGap: 4)
        }
    }

    private func mergedInlineRects(_ rects: [NSRect], maxGap: CGFloat? = nil) -> [NSRect] {
        guard !rects.isEmpty else { return [] }
        let sorted = rects.sorted { lhs, rhs in
            if abs(lhs.midY - rhs.midY) > max(lhs.height, rhs.height) * 0.45 {
                return lhs.midY > rhs.midY
            }
            return lhs.minX < rhs.minX
        }

        var merged: [NSRect] = []
        for rect in sorted {
            guard rect.width > 1, rect.height > 1 else { continue }
            if let last = merged.last {
                let gap = rect.minX - last.maxX
                let verticalOverlap = min(last.maxY, rect.maxY) - max(last.minY, rect.minY)
                let threshold = maxGap ?? max(8, min(last.height, rect.height) * 0.9)
                if gap <= threshold, verticalOverlap > min(last.height, rect.height) * 0.35 {
                    merged[merged.count - 1] = last.union(rect)
                    continue
                }
            }
            merged.append(rect)
        }
        return merged
    }

    private func drawDimMask(excluding rects: [NSRect]) {
        NSColor.black.withAlphaComponent(0.28).setFill()
        bounds.fill()

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.compositingOperation = .destinationOut
        NSColor.black.setFill()
        for rect in rects where rect.width > 1 && rect.height > 1 {
            NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawCopyableTextBackplates(_ rects: [NSRect]) {
        let path = NSBezierPath()
        for rect in rects where rect.width > 1 && rect.height > 1 {
            path.append(NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5))
        }
        NSColor.white.withAlphaComponent(0.24).setFill()
        path.fill()
    }

    private func drawSelectedTextRect(_ rect: NSRect) {
        guard rect.width > 1, rect.height > 1 else { return }
        let path = NSBezierPath(roundedRect: rect, xRadius: 2.5, yRadius: 2.5)
        NSColor.selectedTextBackgroundColor.withAlphaComponent(0.55).setFill()
        path.fill()
    }
}

private final class PanelPinButton: NSButton {
    private var pinned = false
    private let pinSymbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        title = ""
        imagePosition = .imageOnly
        imageScaling = .scaleProportionallyDown
        isBordered = false
        bezelStyle = .regularSquare
        focusRingType = .none
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.borderWidth = 1.2
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.28
        layer?.shadowRadius = 3
        layer?.shadowOffset = NSSize(width: 0, height: -1)
        setPinned(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { false }

    override func layout() {
        super.layout()
        layer?.cornerRadius = min(bounds.width, bounds.height) / 2
        layer?.shadowPath = CGPath(ellipseIn: bounds, transform: nil)
    }

    func setPinned(_ pinned: Bool) {
        self.pinned = pinned
        let label = pinned ? "Unpin dialog" : "Pin dialog"
        let symbolName = pinned ? "pin.fill" : "pin"
        image = NSImage(systemSymbolName: symbolName, accessibilityDescription: label)?
            .withSymbolConfiguration(pinSymbolConfiguration)
        updateAppearance()
        toolTip = label
        setAccessibilityLabel(label)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    private func updateAppearance() {
        contentTintColor = pinned ? .white : .labelColor
        let background = pinned
            ? toolbarAccent.withAlphaComponent(0.96)
            : AdaptiveChrome.floatingBackground
        layer?.backgroundColor = AdaptiveChrome.resolvedCGColor(background, for: effectiveAppearance)
        layer?.borderColor = AdaptiveChrome.resolvedCGColor(
            AdaptiveChrome.border,
            for: effectiveAppearance
        )
    }
}


// MARK: - OCR panel

/// Floating dialog shown after text recognition: the screenshot with
/// selectable line boxes on top, the recognized text below, one copy button.
final class OCRPanel: NSPanel, NSTextViewDelegate {

    private static var current: OCRPanel?
    private static let topMargin: CGFloat = 24

    private let screenshot: NSImage
    private let anchorScreen: NSScreen
    private let panelWidth: CGFloat

    private let padding: CGFloat = 14
    private var panelWidthConstraint: NSLayoutConstraint?
    private var documentWidthConstraint: NSLayoutConstraint?
    private var contentStack: NSStackView!
    private var docView: FlippedView!
    private var clipView: NSClipView!
    private var previewView: OCRPreviewView!

    private var ocrTextView: PanelTextView?
    private var ocrCopyButton: NSButton?
    private var pinButton: PanelPinButton?

    private var keyMonitor: Any?
    private var outsideClickLocalMonitor: Any?
    private var outsideClickGlobalMonitor: Any?
    private var isLiveTextMenuOpen = false
    private var ocrTask: Task<Void, Never>?
    private var liveTextTask: Task<Void, Never>?
    private var recognizedLines: [RecognizedTextLine] = []
    private var recognizedText = ""
    private var ocrReady = false
    private var isPinned = false {
        didSet { pinButton?.setPinned(isPinned) }
    }

    // MARK: Presentation

    static func present(image: NSImage, anchorRect: NSRect, screen: NSScreen) {
        presentTextRecognition(image: image, anchorRect: anchorRect, screen: screen)
    }

    static func presentTextRecognition(image: NSImage, anchorRect: NSRect, screen: NSScreen,
                                       initialResult: OCRResult? = nil) {
        current?.dismiss()
        let panel = OCRPanel(image: image, anchorRect: anchorRect, screen: screen)
        current = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        panel.runOCR(initialResult: initialResult)
    }

    private init(image: NSImage, anchorRect: NSRect, screen: NSScreen) {
        let panelWidth = min(max(anchorRect.width, 360), 500)
        self.screenshot = image
        self.anchorScreen = screen
        self.panelWidth = panelWidth
        let initialFrame = Self.topCenteredFrame(width: panelWidth, height: 320, on: screen)

        super.init(
            contentRect: initialFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        animationBehavior = .none

        buildUI()
        installEventMonitors()
        refreshHeight()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    // MARK: UI

    private func buildUI() {
        let root = AdaptiveChromeSurfaceView(style: .panel, cornerRadius: Brand.radiusLarge, borderWidth: 1)
        contentView = root
        let panelWidthConstraint = root.widthAnchor.constraint(equalToConstant: panelWidth)
        panelWidthConstraint.isActive = true
        self.panelWidthConstraint = panelWidthConstraint

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        root.addSubview(scrollView)
        clipView = scrollView.contentView

        docView = FlippedView()
        docView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = docView

        contentStack = NSStackView()
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 12
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        docView.addSubview(contentStack)
        let documentWidthConstraint = docView.widthAnchor.constraint(equalToConstant: panelWidth - padding * 2)
        self.documentWidthConstraint = documentWidthConstraint

        let pinButton = PanelPinButton()
        pinButton.translatesAutoresizingMaskIntoConstraints = false
        pinButton.target = self
        pinButton.action = #selector(pinTapped)
        self.pinButton = pinButton
        root.addSubview(pinButton)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: root.topAnchor, constant: padding),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: padding),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -padding),
            scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -padding),

            docView.topAnchor.constraint(equalTo: contentStack.topAnchor),
            docView.heightAnchor.constraint(equalTo: contentStack.heightAnchor),
            documentWidthConstraint,

            contentStack.topAnchor.constraint(equalTo: docView.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: docView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: docView.trailingAnchor),

            pinButton.topAnchor.constraint(equalTo: root.topAnchor, constant: 8),
            pinButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -8),
            pinButton.widthAnchor.constraint(equalToConstant: 24),
            pinButton.heightAnchor.constraint(equalToConstant: 24),
        ])

        buildScreenshotCard()
        buildOCRCard()
    }

    private func addStackRow(_ view: NSView) {
        contentStack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
    }

    private func buildScreenshotCard() {
        previewView = OCRPreviewView(image: screenshot)
        previewView.showsLineBoxes = true
        previewView.onSelectText = { [weak self] text, lineIndices, isFinal in
            self?.selectOCRText(text, lineIndices: lineIndices, copyWhenFinal: isFinal)
        }
        previewView.onLiveTextMenuVisibilityChange = { [weak self] isOpen in
            self?.isLiveTextMenuOpen = isOpen
        }

        let size = screenshot.size
        let aspect = size.width > 0 ? size.height / size.width : 0.5
        let contentWidth = panelWidth - padding * 2
        let height = min(max(contentWidth * aspect, 64), 260)
        previewView.heightAnchor.constraint(equalToConstant: height).isActive = true

        addStackRow(previewView)
    }

    private func buildOCRCard() {
        let card = makeCard()
        let inner = makeCardStack()
        card.addSubview(inner)
        pin(inner, to: card, inset: 12)

        let title = makeLabel(L10n.ocrTextHeader, size: 12, weight: .semibold, alpha: 0.92)
        let copyButton = makeSmallButton(L10n.ocrCopy, action: #selector(copyOCRTapped))
        copyButton.target = self
        copyButton.isEnabled = false
        ocrCopyButton = copyButton

        let retryButton = makeSmallButton(L10n.ocrRetry, action: #selector(retryOCRTapped))
        retryButton.target = self
        let header = NSStackView(views: [title, flexSpacer(), retryButton, copyButton])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.translatesAutoresizingMaskIntoConstraints = false
        inner.addArrangedSubview(header)
        header.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true

        let (scroll, textView) = makeTextScroll(editable: false, height: 116)
        textView.delegate = self
        textView.string = L10n.ocrRecognizing
        textView.textColor = .secondaryLabelColor
        ocrTextView = textView
        inner.addArrangedSubview(scroll)
        scroll.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true

        addStackRow(card)
    }

    // MARK: OCR

    @objc private func retryOCRTapped() { runOCR() }

    private func runOCR(initialResult: OCRResult? = nil) {
        ocrTask?.cancel()
        liveTextTask?.cancel()
        ocrReady = false
        applyOCRResult(text: "", lines: [], liveTextAnalysis: nil)
        ocrTextView?.isEditable = false
        ocrTextView?.string = L10n.ocrRecognizing
        ocrTextView?.textColor = .secondaryLabelColor
        ocrCopyButton?.isEnabled = false
        let screenshot = screenshot
        ocrTask = Task { @MainActor [weak self] in
            let result: OCRResult
            do {
                if let initialResult {
                    result = initialResult
                } else {
                    result = try await OCRService.recognizeResult(image: screenshot)
                }
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.ocrTask = nil
                self.ocrReady = true
                self.ocrTextView?.string = error.localizedDescription
                self.ocrTextView?.textColor = Brand.alert
                self.refreshHeight()
                return
            }

            guard !Task.isCancelled, let self else { return }
            self.ocrTask = nil
            self.applyOCRResult(text: result.text, lines: result.lines, liveTextAnalysis: nil)
            self.ocrReady = true
            self.finishTextRecognition()
            self.refreshHeight()
            if result.provider == .apple, !result.text.isEmpty {
                self.startLiveTextAnalysis()
            }
        }
    }

    private func startLiveTextAnalysis() {
        let screenshot = screenshot
        liveTextTask = Task { @MainActor [weak self] in
            let analysis = await OCRService.analyzeText(image: screenshot)
            guard !Task.isCancelled, let self else { return }
            self.liveTextTask = nil
            self.previewView.applyLiveTextAnalysis(analysis)
        }
    }

    private static func text(from lines: [RecognizedTextLine]) -> String {
        lines.map(\.text).joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func applyOCRResult(text: String, lines: [RecognizedTextLine], liveTextAnalysis: ImageAnalysis?) {
        recognizedLines = lines
        previewView.lines = lines
        previewView.applyLiveTextAnalysis(liveTextAnalysis)
        recognizedText = text
    }

    private func finishTextRecognition() {
        guard let textView = ocrTextView, let copyButton = ocrCopyButton else { return }
        if recognizedText.isEmpty {
            textView.isEditable = false
            textView.string = L10n.ocrNoText
            textView.textColor = .secondaryLabelColor
            copyButton.isEnabled = false
        } else {
            textView.string = recognizedText
            textView.textColor = .labelColor
            textView.isEditable = true
            copyButton.isEnabled = true
        }
    }

    func textDidChange(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView,
              textView === ocrTextView else { return }
        recognizedText = textView.string
        previewView.clearTextSelection()
        ocrCopyButton?.isEnabled = !recognizedText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    private func selectOCRText(_ text: String, lineIndices: [Int], copyWhenFinal: Bool) {
        let selectedIndices = contiguousOCRLineIndices(covering: lineIndices)
        guard let textView = ocrTextView, !selectedIndices.isEmpty else {
            ocrTextView?.selectedRange = NSRange(location: 0, length: 0)
            return
        }

        if let range = textRange(forOCRLineIndices: selectedIndices) {
            makeFirstResponder(textView)
            textView.selectedRange = range
            textView.scrollRangeToVisible(range)
        }

        guard copyWhenFinal else { return }
        let selectedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selectedText.isEmpty else { return }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(selectedText, forType: .string)
        ToastWindow.show(
            message: selectedIndices.count == 1 ? L10n.ocrLineCopied : L10n.ocrCopied,
            duration: 0.9
        )
        if let button = ocrCopyButton {
            flashButton(button, to: L10n.ocrCopied, restore: L10n.ocrCopy)
        }
    }

    private func contiguousOCRLineIndices(covering indices: [Int]) -> [Int] {
        let valid = indices.filter { recognizedLines.indices.contains($0) }
        guard let first = valid.min(), let last = valid.max() else { return [] }
        return Array(first...last)
    }

    private func textRange(forOCRLineIndices indices: [Int]) -> NSRange? {
        guard recognizedText == Self.text(from: recognizedLines) else { return nil }
        guard let first = indices.first, let last = indices.last,
              recognizedLines.indices.contains(first),
              recognizedLines.indices.contains(last) else {
            return nil
        }

        var location = 0
        for index in 0..<first {
            location += (recognizedLines[index].text as NSString).length
            location += 1
        }

        var length = 0
        for index in first...last {
            length += (recognizedLines[index].text as NSString).length
            if index != last {
                length += 1
            }
        }
        return NSRange(location: location, length: length)
    }

    // MARK: Sizing

    private func refreshHeight() {
        lockPanelWidth()
        contentView?.layoutSubtreeIfNeeded()
        let contentHeight = contentStack.fittingSize.height
        let desired = contentHeight + padding * 2
        let visible = anchorScreen.visibleFrame
        let maxHeight = min(700, visible.height - Self.topMargin - 16)
        let height = max(180, min(desired, maxHeight))

        setFrame(Self.topCenteredFrame(width: panelWidth, height: height, on: anchorScreen),
                 display: true, animate: false)
    }

    private func lockPanelWidth() {
        panelWidthConstraint?.constant = panelWidth
        documentWidthConstraint?.constant = panelWidth - padding * 2
        guard abs(frame.width - panelWidth) > 0.5 else { return }
        setFrame(Self.topCenteredFrame(width: panelWidth, height: frame.height, on: anchorScreen),
                 display: false, animate: false)
    }

    private static func topCenteredFrame(width: CGFloat, height: CGFloat, on screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame
        let originX = min(max(visible.midX - width / 2, visible.minX), visible.maxX - width)
        let originY = visible.maxY - topMargin - height
        return NSRect(x: originX, y: max(originY, visible.minY), width: width, height: height)
    }

    // MARK: Actions

    @objc private func pinTapped() {
        isPinned.toggle()
    }

    @objc private func copyOCRTapped() {
        guard ocrReady else { return }
        if previewView.copySelectedOverlayTextToClipboard() || previewView.copySelectedLiveTextToClipboard() {
            if let button = ocrCopyButton {
                flashButton(button, to: L10n.ocrCopied, restore: L10n.ocrCopy)
            }
            return
        }
        guard !recognizedText.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(recognizedText, forType: .string)
        if let button = ocrCopyButton {
            flashButton(button, to: L10n.ocrCopied, restore: L10n.ocrCopy)
        }
    }

    private func installEventMonitors() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self else { return event }
            if event.keyCode == 53 { // Escape
                self.dismiss()
                return nil
            }
            if self.handleOCRImageKeyEquivalent(event) {
                return nil
            }
            return event
        }

        let mouseDownMask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        outsideClickLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseDownMask) { [weak self] event in
            self?.dismissForOutsideClickIfNeeded(event)
            return event
        }
        outsideClickGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseDownMask) { [weak self] event in
            self?.dismissForOutsideClickIfNeeded(event)
        }
    }

    private func dismissForOutsideClickIfNeeded(_ event: NSEvent) {
        guard !isPinned,
              !isLiveTextMenuOpen,
              isVisible,
              !(event.window === self || event.windowNumber == windowNumber),
              !eventTargetsPanelThroughCaptureOverlay(event)
        else { return }
        dismiss()
    }

    private func eventTargetsPanelThroughCaptureOverlay(_ event: NSEvent) -> Bool {
        guard let eventWindow = event.window,
              eventWindow.contentView is SelectionView
        else {
            return false
        }
        let screenPoint = eventWindow.convertPoint(toScreen: event.locationInWindow)
        return frame.insetBy(dx: -24, dy: -24).contains(screenPoint)
    }

    private func handleOCRImageKeyEquivalent(_ event: NSEvent) -> Bool {
        guard !(firstResponder is NSTextView),
              event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command else {
            return false
        }

        switch event.charactersIgnoringModifiers {
        case "a":
            return previewView.selectAllOverlayText() || previewView.selectAllLiveText()
        case "c":
            guard previewView.copySelectedOverlayTextToClipboard()
                    || previewView.copySelectedLiveTextToClipboard() else {
                return false
            }
            if let button = ocrCopyButton {
                flashButton(button, to: L10n.ocrCopied, restore: L10n.ocrCopy)
            }
            return true
        default:
            return false
        }
    }

    func dismiss() {
        ocrTask?.cancel()
        ocrTask = nil
        liveTextTask?.cancel()
        liveTextTask = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }
        if let outsideClickLocalMonitor {
            NSEvent.removeMonitor(outsideClickLocalMonitor)
            self.outsideClickLocalMonitor = nil
        }
        if let outsideClickGlobalMonitor {
            NSEvent.removeMonitor(outsideClickGlobalMonitor)
            self.outsideClickGlobalMonitor = nil
        }
        isLiveTextMenuOpen = false
        orderOut(nil)
        if OCRPanel.current === self { OCRPanel.current = nil }
    }

    // MARK: Shared builders

    private func makeCard() -> NSView {
        let v = AdaptiveChromeSurfaceView(style: .card, cornerRadius: Brand.radiusLarge, borderWidth: 1)
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }

    private func makeCardStack() -> NSStackView {
        let s = NSStackView()
        s.orientation = .vertical
        s.alignment = .leading
        s.spacing = 8
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }
}

// MARK: - Free-standing builders

func makeLabel(_ text: String, size: CGFloat, weight: NSFont.Weight, alpha: CGFloat) -> NSTextField {
    let l = NSTextField(labelWithString: text)
    l.font = NSFont.systemFont(ofSize: size, weight: weight)
    l.textColor = NSColor.labelColor.withAlphaComponent(alpha)
    l.translatesAutoresizingMaskIntoConstraints = false
    return l
}

func flexSpacer() -> NSView {
    let v = NSView()
    v.translatesAutoresizingMaskIntoConstraints = false
    v.setContentHuggingPriority(.init(1), for: .horizontal)
    v.setContentCompressionResistancePriority(.init(1), for: .horizontal)
    return v
}

func makeSmallButton(_ title: String, action: Selector) -> NSButton {
    let b = NSButton(title: title, target: nil, action: action)
    b.bezelStyle = .rounded
    b.controlSize = .small
    b.font = NSFont.systemFont(ofSize: 11)
    b.translatesAutoresizingMaskIntoConstraints = false
    return b
}

func configureIconButton(_ button: NSButton, symbolName: String, label: String) {
    button.title = ""
    button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: label)
    button.imagePosition = .imageOnly
    button.imageScaling = .scaleProportionallyDown
    button.isBordered = false
    button.bezelStyle = .regularSquare
    button.controlSize = .small
    button.contentTintColor = .secondaryLabelColor
    button.toolTip = label
    button.setAccessibilityLabel(label)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.widthAnchor.constraint(equalToConstant: 24).isActive = true
    button.heightAnchor.constraint(equalToConstant: 24).isActive = true
}

func pin(_ child: NSView, to parent: NSView, inset: CGFloat) {
    NSLayoutConstraint.activate([
        child.topAnchor.constraint(equalTo: parent.topAnchor, constant: inset),
        child.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: inset),
        child.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -inset),
        child.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -inset),
    ])
}

func configureExpandingTextView(_ textView: PanelTextView) {
    textView.translatesAutoresizingMaskIntoConstraints = false
    textView.isEditable = false
    textView.isSelectable = true
    textView.isRichText = false
    textView.drawsBackground = false
    textView.font = NSFont.systemFont(ofSize: 12)
    textView.textColor = .labelColor
    textView.textContainerInset = NSSize(width: 6, height: 6)
    textView.isVerticallyResizable = false
    textView.isHorizontallyResizable = false
    textView.textContainer?.widthTracksTextView = true
    textView.textContainer?.heightTracksTextView = false
    textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
}

/// A bordered scroll view wrapping a `PanelTextView` of fixed height.
func makeTextScroll(editable: Bool, height: CGFloat) -> (NSScrollView, PanelTextView) {
    let scroll = AdaptiveTextScrollView()
    scroll.translatesAutoresizingMaskIntoConstraints = false
    scroll.hasVerticalScroller = false
    scroll.hasHorizontalScroller = false
    scroll.autohidesScrollers = true
    scroll.drawsBackground = true
    scroll.backgroundColor = AdaptiveChrome.cardBackground
    scroll.borderType = .noBorder
    scroll.wantsLayer = true
    scroll.layer?.cornerRadius = 6
    scroll.layer?.cornerCurve = .continuous
    scroll.layer?.masksToBounds = true
    scroll.heightAnchor.constraint(equalToConstant: height).isActive = true

    let textView = PanelTextView()
    textView.isEditable = editable
    textView.isSelectable = true
    textView.isRichText = false
    textView.drawsBackground = false
    textView.font = NSFont.systemFont(ofSize: 12)
    textView.textColor = .labelColor
    textView.textContainerInset = NSSize(width: 6, height: 6)
    textView.isVerticallyResizable = true
    textView.isHorizontallyResizable = false
    textView.autoresizingMask = [.width]
    textView.minSize = NSSize(width: 0, height: height)
    textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    textView.textContainer?.widthTracksTextView = true
    textView.textContainer?.heightTracksTextView = false
    textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
    scroll.documentView = textView
    return (scroll, textView)
}

/// Flips a button title to a confirmation string for a moment.
func flashButton(_ button: NSButton, to confirm: String, restore: String) {
    button.title = confirm
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak button] in
        button?.title = restore
    }
}

func flashIconButton(_ button: NSButton, symbolName: String, restoreSymbolName: String) {
    button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: L10n.ocrCopied)
    button.contentTintColor = Brand.accent
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak button] in
        button?.image = NSImage(systemSymbolName: restoreSymbolName, accessibilityDescription: L10n.ocrCopy)
        button?.contentTintColor = .secondaryLabelColor
    }
}

private final class AdaptiveTextScrollView: NSScrollView {
    override func tile() {
        super.tile()
        guard let textView = documentView as? NSTextView,
              let container = textView.textContainer else { return }
        let width = contentView.bounds.width
        guard width > 0 else { return }
        if abs(textView.frame.width - width) > 0.5 {
            textView.setFrameSize(NSSize(width: width, height: max(textView.frame.height, contentSize.height)))
        }
        let textWidth = max(width - textView.textContainerInset.width * 2, 1)
        if abs(container.containerSize.width - textWidth) > 0.5 {
            container.containerSize = NSSize(width: textWidth, height: CGFloat.greatestFiniteMagnitude)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyAppearance()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyAppearance()
    }

    private func applyAppearance() {
        backgroundColor = AdaptiveChrome.cardBackground
        layer?.borderWidth = 1
        layer?.borderColor = AdaptiveChrome.resolvedCGColor(
            AdaptiveChrome.border,
            for: effectiveAppearance
        )
    }
}

private extension Character {
    var isCJKLike: Bool {
        unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3040...0x30FF,
                 0x3400...0x4DBF,
                 0x4E00...0x9FFF,
                 0xAC00...0xD7AF,
                 0xF900...0xFAFF:
                return true
            default:
                return false
            }
        }
    }
}
