import AppKit

/// Stable identifier for every button that can appear in the editor's
/// toolbars. Raw values are persisted in `UserDefaults`, so existing cases
/// must never be renamed — only added or deprecated.
enum ToolbarItemID: String, Codable, CaseIterable {
    // Annotation tools (toggle an `EditTool`)
    case rectangle
    case ellipse
    case arrow
    case line
    case pen
    case marker
    case spotlight
    case mosaic
    case eraser
    case magnifier
    case numbered
    case text
    case qrCode
    case emoji
    case insertImage
    // Stateful actions
    case colorPicker
    case undo
    case redo
    case moveSelection
    case scrollCapture
    case rotate
    case beautify
    case ocr
    // Output actions
    case save
    case pin
    case record
    case close
    case confirm
    // Dividers: a pool of sixteen, each used at most once. Settings shows one
    // spare at a time, so dragging it out reads as adding a new divider.
    case divider1
    case divider2
    case divider3
    case divider4
    case divider5
    case divider6
    case divider7
    case divider8
    case divider9
    case divider10
    case divider11
    case divider12
    case divider13
    case divider14
    case divider15
    case divider16
    // The "More" button that opens the overflow menu. Lives on the primary
    // bar only; its position there is the user's choice.
    case more
}

extension ToolbarLayout {
    /// The hidden grid shows only the first spare divider; the rest wait
    /// behind it and appear one by one as dividers are dragged out.
    static func displayedHidden(_ hidden: [ToolbarItemID]) -> [ToolbarItemID] {
        var shownSpare = false
        return hidden.filter { id in
            guard id.isDivider else { return true }
            defer { shownSpare = true }
            return !shownSpare
        }
    }
}

extension ToolbarItemID {
    static let dividers: [ToolbarItemID] = [.divider1, .divider2, .divider3, .divider4, .divider5, .divider6, .divider7, .divider8, .divider9, .divider10, .divider11, .divider12, .divider13, .divider14, .divider15, .divider16]
    var isDivider: Bool { Self.dividers.contains(self) }
}

extension ToolbarItemID {
    /// How the button behaves — drives which `on*` callback it fires and
    /// whether it carries a persistent selected/active state.
    enum Kind {
        /// Annotation tool — selecting it toggles an `EditTool`.
        case toggleTool
        /// Has an on/off state but is not an `EditTool` (scroll capture, beautify).
        case toggleAction
        /// Fires once on click, no persistent state.
        case momentary
        /// Press-and-drag handle (move selection) — not a tappable button.
        case dragHandle
        /// Zone divider — draws as a gap in the bar, never a button.
        case divider
        /// Opens the overflow menu; pinned to the primary bar.
        case overflowMenu
    }

    var kind: Kind {
        switch self {
        case .rectangle, .ellipse, .arrow, .line, .pen, .marker, .spotlight, .mosaic, .eraser, .magnifier, .numbered, .text, .emoji:
            return .toggleTool
        case .scrollCapture, .rotate, .beautify, .qrCode:
            return .toggleAction
        case .moveSelection:
            return .dragHandle
        case .insertImage, .colorPicker, .undo, .redo, .ocr, .save, .pin, .record, .close, .confirm:
            return .momentary
        case .divider1, .divider2, .divider3, .divider4, .divider5, .divider6, .divider7, .divider8, .divider9, .divider10, .divider11, .divider12, .divider13, .divider14, .divider15, .divider16:
            return .divider
        case .more:
            return .overflowMenu
        }
    }

    /// The annotation tool a `toggleTool` item maps to; `nil` for all others.
    var editTool: EditTool? {
        switch self {
        case .rectangle: return .rectangle
        case .ellipse:   return .ellipse
        case .arrow:     return .arrow
        case .line:      return .line
        case .pen:       return .pen
        case .marker:    return .marker
        case .spotlight: return .spotlight
        case .mosaic:    return .mosaic
        case .eraser:    return .eraser
        case .magnifier: return .magnifier
        case .numbered:  return .numbered
        case .text:      return .text
        case .emoji:     return .emoji
        default:         return nil
        }
    }

    var symbolName: String {
        switch self {
        case .rectangle:     return "rectangle"
        case .ellipse:       return "circle"
        case .arrow:         return "arrow.up.right"
        case .line:          return "line.diagonal"
        case .pen:           return "pencil"
        case .marker:        return "highlighter"
        case .spotlight:     return "rectangle.inset.filled"
        case .mosaic:        return "squareshape.split.3x3"
        case .eraser:        return "eraser"
        case .magnifier:     return "plus.magnifyingglass"
        case .numbered:      return "1.circle"
        case .text:          return "character"
        case .qrCode:        return "qrcode.viewfinder"
        case .emoji:         return "face.smiling"
        case .insertImage:   return "photo"
        case .colorPicker:   return "eyedropper"
        case .undo:          return "arrow.uturn.backward"
        case .redo:          return "arrow.uturn.forward"
        case .moveSelection: return "arrow.up.and.down.and.arrow.left.and.right"
        case .scrollCapture: return "arrow.up.and.down.text.horizontal"
        case .rotate:        return "rotate.left"
        case .beautify:      return "sparkles"
        case .ocr:           return "text.viewfinder"
        case .save:          return "arrow.down.to.line"
        case .pin:           return "pin"
        case .record:        return "video"
        case .close:         return "xmark"
        case .confirm:       return "checkmark"
        case .divider1, .divider2, .divider3, .divider4, .divider5, .divider6, .divider7, .divider8, .divider9, .divider10, .divider11, .divider12, .divider13, .divider14, .divider15, .divider16:
            return "rectangle.portrait"
        case .more:          return "ellipsis"
        }
    }

    /// A thin vertical bar standing in for a divider wherever a glyph is drawn.
    private static func dividerImage(pointSize: CGFloat) -> NSImage {
        let side = (pointSize * 1.15).rounded()
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            let w: CGFloat = max(1.5, (pointSize / 9).rounded())
            NSColor.black.setFill()
            NSRect(x: (rect.midX - w / 2).rounded(), y: rect.minY + 1, width: w, height: rect.height - 2).fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    /// Keep the OCR symbol's Chinese glyph fixed regardless of the system locale.
    func iconImage(pointSize: CGFloat) -> NSImage? {
        if isDivider { return Self.dividerImage(pointSize: pointSize) }
        guard let base = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) else {
            return nil
        }
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium, scale: .medium)
        let locale: Locale? = switch self {
        case .ocr: Locale(identifier: "zh-Hans")
        case .text: Locale(identifier: "en")
        default: nil
        }
        return (locale.map { base.withLocale($0) } ?? base).withSymbolConfiguration(config)
    }

    var localizedTitle: String {
        switch self {
        case .rectangle:     return L10n.tipRectangle
        case .ellipse:       return L10n.tipEllipse
        case .arrow:         return L10n.tipArrow
        case .line:          return L10n.tipLine
        case .pen:           return L10n.tipPen
        case .marker:        return L10n.tipMarker
        case .spotlight:     return L10n.tipSpotlight
        case .mosaic:        return L10n.tipMosaic
        case .eraser:        return L10n.tipEraser
        case .magnifier:     return L10n.tipMagnifier
        case .numbered:      return L10n.tipNumbered
        case .text:          return L10n.tipText
        case .qrCode:        return L10n.tipQRCode
        case .emoji:         return L10n.tipEmoji
        case .insertImage:   return L10n.tipInsertImage
        case .colorPicker:   return L10n.tipColorPicker
        case .undo:          return L10n.tipUndo
        case .redo:          return L10n.tipRedo
        case .moveSelection: return L10n.tipMoveSelection
        case .scrollCapture: return L10n.tipScrollCapture
        case .rotate:        return L10n.tipRotate
        case .beautify:      return L10n.tipBeautify
        case .ocr:           return L10n.tipOCR
        case .save:          return L10n.tipSave
        case .pin:           return L10n.tipPin
        case .record:        return L10n.tipRecord
        case .close:         return L10n.tipCancel
        case .confirm:       return L10n.tipConfirm
        case .divider1, .divider2, .divider3, .divider4, .divider5, .divider6, .divider7, .divider8, .divider9, .divider10, .divider11, .divider12, .divider13, .divider14, .divider15, .divider16:
            return L10n.tipDivider
        case .more:          return L10n.tipMore
        }
    }

    /// Localized hover-tooltip text with the current configured shortcut.
    var tooltip: String {
        guard let shortcut = editorShortcutDisplay else { return localizedTitle }
        return "\(localizedTitle) (\(shortcut))"
    }

    var editorShortcutDisplay: String? {
        guard supportsEditorShortcut else { return nil }
        return EditorShortcutRegistry.displayString(for: .toolbar(self))
    }

    /// Icon tint in the resting state.
    var normalColor: NSColor {
        switch self {
        case .close, .more: return Brand.text.withAlphaComponent(0.55)
        case .confirm: return Brand.accent
        default:       return Brand.text.withAlphaComponent(0.85)
        }
    }

    /// Icon tint while selected/active. For `momentary` items this equals
    /// `normalColor` — they never enter a selected state.
    var selectedColor: NSColor {
        switch kind {
        case .toggleTool, .toggleAction:
            return toolbarAccent
        case .momentary, .dragHandle, .divider, .overflowMenu:
            return normalColor
        }
    }
}


/// User-customizable assignment of every toolbar item to the primary
/// (horizontal) toolbar, the side (vertical) toolbar, or hidden.
struct ToolbarLayout: Equatable {
    var primary: [ToolbarItemID]
    var side: [ToolbarItemID]
    var hidden: [ToolbarItemID]

    /// Canonical left-to-right order. Used for the default layout and to
    /// place any newly-introduced tool that an older persisted layout never
    /// recorded.
    static let canonicalOrder: [ToolbarItemID] = [
        .rectangle, .ellipse, .line, .arrow, .pen, .marker, .spotlight, .mosaic, .eraser, .numbered, .text, .emoji, .insertImage,
        .colorPicker, .magnifier, .undo, .redo, .moveSelection, .scrollCapture, .rotate, .beautify, .qrCode, .ocr,
        .save, .pin, .record, .close, .confirm,
    ]

    /// Default layout: annotation tools + edit actions on the primary
    /// (horizontal) toolbar; capture/output actions on the side (vertical)
    /// toolbar.
    static var `default`: ToolbarLayout {
        ToolbarLayout(
            primary: [
                .close, .divider1,
                .rectangle, .ellipse, .arrow, .line, .pen, .text, .mosaic, .numbered, .divider2,
                .undo, .redo, .moveSelection, .divider3,
                .ocr, .save, .pin, .confirm, .divider4, .more,
            ],
            side: [.marker, .eraser, .scrollCapture, .colorPicker, .magnifier, .rotate, .record],
            hidden: [.spotlight, .beautify, .qrCode, .emoji, .insertImage, .divider5]
        )
    }

    /// Drops duplicate / unknown ids and slots any tool missing from all
    /// three buckets next to its canonical neighbour, so the result always
    /// covers every `ToolbarItemID` exactly once regardless of app-version
    /// drift. A newly-introduced tool lands beside its siblings (e.g. `line`
    /// after `ellipse`) instead of being dumped at the end of the bar.
    func normalized() -> ToolbarLayout {
        var seen = Set<ToolbarItemID>()
        func dedup(_ ids: [ToolbarItemID]) -> [ToolbarItemID] {
            ids.filter { seen.insert($0).inserted }
        }
        var p = dedup(primary)
        var s = dedup(side)
        var h = dedup(hidden)

        let missing = Self.canonicalOrder.filter { !seen.contains($0) }
        for item in missing {
            // Existing layouts put scroll capture on the side bar. Anchor the
            // new rotation action to Beautify so upgrading preserves its place.
            if item == .rotate {
                if let index = p.firstIndex(of: .beautify) {
                    p.insert(item, at: index)
                } else if let index = s.firstIndex(of: .beautify) {
                    s.insert(item, at: index)
                } else if let index = h.firstIndex(of: .beautify) {
                    h.insert(item, at: index)
                } else {
                    p.append(item)
                }
                seen.insert(item)
                continue
            }
            guard let canonicalIdx = Self.canonicalOrder.firstIndex(of: item) else { continue }
            // Walk back through the canonical order to the nearest sibling
            // that's already placed, then drop the new tool right after it
            // in whichever bucket that sibling lives in.
            var placed = false
            for prevIdx in stride(from: canonicalIdx - 1, through: 0, by: -1) {
                let prev = Self.canonicalOrder[prevIdx]
                if let i = p.firstIndex(of: prev) { p.insert(item, at: i + 1); placed = true; break }
                if let i = s.firstIndex(of: prev) { s.insert(item, at: i + 1); placed = true; break }
                if let i = h.firstIndex(of: prev) { h.insert(item, at: i + 1); placed = true; break }
            }
            if !placed { p.insert(item, at: 0) }
            seen.insert(item)
        }
        // "More" belongs on the primary bar. A layout saved before it was
        // movable gets it at the end behind a spare divider, as it used to look.
        if let i = s.firstIndex(of: .more) { s.remove(at: i); p.append(.more) }
        if let i = h.firstIndex(of: .more) { h.remove(at: i); p.append(.more) }
        if !seen.contains(.more) {
            if p.last?.isDivider == false,
               let spare = ToolbarItemID.dividers.first(where: { !seen.contains($0) || h.contains($0) }) {
                h.removeAll { $0 == spare }
                p.append(spare)
                seen.insert(spare)
            }
            p.append(.more)
            seen.insert(.more)
        }
        for divider in ToolbarItemID.dividers where !seen.contains(divider) {
            h.append(divider)
            seen.insert(divider)
        }
        return ToolbarLayout(primary: p, side: s, hidden: h)
    }

    /// The families the bar used to zone by before dividers became user
    /// data. Still used to translate a pre-divider layout once.
    static let shapeFamily: [ToolbarItemID] = [.rectangle, .ellipse, .arrow, .line]
    static let outcomeFamily: Set<ToolbarItemID> = [.ocr, .save, .pin, .record, .confirm]
    static let editFamily: Set<ToolbarItemID> = [.undo, .redo]

    /// Whether any bucket already carries a divider, i.e. the layout was
    /// saved by a build that knows about them.
    var hasDividers: Bool {
        (primary + side + hidden).contains { $0.isDivider }
    }

    /// Rebuilds the old automatic zoning (close | tools | edit | outcomes)
    /// out of explicit dividers so an upgraded install looks unchanged.
    func withLegacyZonesAsDividers() -> ToolbarLayout {
        guard !hasDividers else { return self }
        var leading: [ToolbarItemID] = [], tools: [ToolbarItemID] = []
        var edit: [ToolbarItemID] = [], outcomes: [ToolbarItemID] = []
        for id in primary {
            if id == .close { leading.append(id) }
            else if Self.outcomeFamily.contains(id) { outcomes.append(id) }
            else if Self.editFamily.contains(id) { edit.append(id) }
            else { tools.append(id) }
        }
        var zones = [leading, tools, edit, outcomes].filter { !$0.isEmpty }
        var p: [ToolbarItemID] = []
        var pool = ToolbarItemID.dividers
        if !zones.isEmpty {
            p = zones.removeFirst()
            for zone in zones {
                if !pool.isEmpty { p.append(pool.removeFirst()) }
                p.append(contentsOf: zone)
            }
        }
        return ToolbarLayout(primary: p, side: side, hidden: hidden + pool)
    }
}

extension ToolbarLayout {
    /// Builds a layout from a persisted `[bucket: [rawValue]]` dictionary,
    /// silently skipping any raw value no longer backed by a `ToolbarItemID`.
    init(dictionary: [String: [String]]) {
        func parse(_ key: String) -> [ToolbarItemID] {
            (dictionary[key] ?? []).compactMap(ToolbarItemID.init(rawValue:))
        }
        self.init(
            primary: parse("primary"),
            side: parse("side"),
            hidden: parse("hidden")
        )
        self = withLegacyZonesAsDividers()
    }

    /// Plain `[String: [String]]` form suitable for `UserDefaults`.
    var dictionary: [String: [String]] {
        [
            "primary": primary.map(\.rawValue),
            "side": side.map(\.rawValue),
            "hidden": hidden.map(\.rawValue),
        ]
    }
}

extension Defaults {
    /// Persisted editor toolbar layout. Always returned normalized, so
    /// callers can rely on every tool being present exactly once.
    static var toolbarLayout: ToolbarLayout {
        get {
            guard let dict = UserDefaults.standard
                .dictionary(forKey: "editor.toolbarLayout") as? [String: [String]]
            else {
                return .default
            }
            var layout = ToolbarLayout(dictionary: dict).normalized()
            // 2026-10-24: the move handle joined the default bar. Promote it
            // once for layouts saved before that, next to undo/redo.
            let promotedKey = "editor.toolbarLayout.moveHandlePromoted"
            if !UserDefaults.standard.bool(forKey: promotedKey) {
                UserDefaults.standard.set(true, forKey: promotedKey)
                if let at = layout.hidden.firstIndex(of: .moveSelection) {
                    var hidden = layout.hidden
                    hidden.remove(at: at)
                    var primary = layout.primary
                    if let i = primary.lastIndex(where: { $0 == .redo || $0 == .undo }) {
                        primary.insert(.moveSelection, at: i + 1)
                    } else if let i = primary.firstIndex(of: .confirm) {
                        primary.insert(.moveSelection, at: i)
                    } else {
                        primary.append(.moveSelection)
                    }
                    layout = ToolbarLayout(primary: primary, side: layout.side, hidden: hidden)
                    UserDefaults.standard.set(layout.normalized().dictionary, forKey: "editor.toolbarLayout")
                }
            }
            return layout
        }
        set {
            UserDefaults.standard.set(
                newValue.normalized().dictionary,
                forKey: "editor.toolbarLayout"
            )
        }
    }
}
