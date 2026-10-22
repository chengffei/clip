import AppKit

struct BeautifyPreset: Equatable {
    let id: String
    let displayName: String
    let startColor: NSColor
    let endColor: NSColor
    let angleDegrees: CGFloat
    let isWallpaper: Bool
    let isTransparent: Bool

    init(
        id: String,
        displayName: String,
        startColor: NSColor,
        endColor: NSColor,
        angleDegrees: CGFloat,
        isWallpaper: Bool = false,
        isTransparent: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.startColor = startColor
        self.endColor = endColor
        self.angleDegrees = angleDegrees
        self.isWallpaper = isWallpaper
        self.isTransparent = isTransparent
    }

    static func == (lhs: BeautifyPreset, rhs: BeautifyPreset) -> Bool {
        lhs.id == rhs.id
    }

    /// Pure alpha background: export keeps transparent padding and rounded
    /// corners; live preview draws a checkerboard so the empty areas stay
    /// visible in the editor.
    static let transparent = BeautifyPreset(
        id: "transparent",
        displayName: L10n.beautifyPresetTransparent,
        startColor: .clear,
        endColor: .clear,
        angleDegrees: 0,
        isTransparent: true
    )

    static let wallpaper = BeautifyPreset(
        id: "wallpaper",
        displayName: L10n.beautifyPresetWallpaper,
        startColor: .clear,
        endColor: .clear,
        angleDegrees: 0,
        isWallpaper: true
    )

    /// Compact set shown directly in the editor and Settings. The expanded
    /// picker exposes `defaults`, which appends the larger gradient catalog.
    static let primaryPresets: [BeautifyPreset] = [
        transparent,
        wallpaper,
        BeautifyPreset(
            id: "peach-blue",
            displayName: L10n.beautifyPresetPeachBlue,
            startColor: NSColor(red: 0xFD/255.0, green: 0xE8/255.0, blue: 0xEF/255.0, alpha: 1),
            endColor:   NSColor(red: 0xC7/255.0, green: 0xD7/255.0, blue: 0xF2/255.0, alpha: 1),
            angleDegrees: 135
        ),
        BeautifyPreset(
            id: "mint-teal",
            displayName: L10n.beautifyPresetMintTeal,
            startColor: NSColor(red: 0xD4/255.0, green: 0xF1/255.0, blue: 0xE5/255.0, alpha: 1),
            endColor:   NSColor(red: 0xA7/255.0, green: 0xD8/255.0, blue: 0xC6/255.0, alpha: 1),
            angleDegrees: 135
        ),
        BeautifyPreset(
            id: "peach-pink",
            displayName: L10n.beautifyPresetPeachPink,
            startColor: NSColor(red: 0xFD/255.0, green: 0xE1/255.0, blue: 0xD3/255.0, alpha: 1),
            endColor:   NSColor(red: 0xF9/255.0, green: 0xA8/255.0, blue: 0xA8/255.0, alpha: 1),
            angleDegrees: 135
        ),
        BeautifyPreset(
            id: "blue-purple",
            displayName: L10n.beautifyPresetBluePurple,
            startColor: NSColor(red: 0xC9/255.0, green: 0xD6/255.0, blue: 0xFF/255.0, alpha: 1),
            endColor:   NSColor(red: 0xE2/255.0, green: 0xB0/255.0, blue: 0xFF/255.0, alpha: 1),
            angleDegrees: 135
        ),
        BeautifyPreset(
            id: "warm-orange",
            displayName: L10n.beautifyPresetWarmOrange,
            startColor: NSColor(red: 0xFE/255.0, green: 0xF3/255.0, blue: 0xC7/255.0, alpha: 1),
            endColor:   NSColor(red: 0xFB/255.0, green: 0xBF/255.0, blue: 0x85/255.0, alpha: 1),
            angleDegrees: 135
        ),
        BeautifyPreset(
            id: "teal-pink",
            displayName: L10n.beautifyPresetTealPink,
            startColor: NSColor(red: 0xA8/255.0, green: 0xED/255.0, blue: 0xEA/255.0, alpha: 1),
            endColor:   NSColor(red: 0xFE/255.0, green: 0xD6/255.0, blue: 0xE3/255.0, alpha: 1),
            angleDegrees: 135
        ),
        BeautifyPreset(
            id: "deep-purple",
            displayName: L10n.beautifyPresetDeepPurple,
            startColor: NSColor(red: 0x66/255.0, green: 0x7E/255.0, blue: 0xEA/255.0, alpha: 1),
            endColor:   NSColor(red: 0x76/255.0, green: 0x4B/255.0, blue: 0xA2/255.0, alpha: 1),
            angleDegrees: 135
        ),
        BeautifyPreset(
            id: "neutral-gray",
            displayName: L10n.beautifyPresetNeutralGray,
            startColor: NSColor(red: 0xE9/255.0, green: 0xEC/255.0, blue: 0xEF/255.0, alpha: 1),
            endColor:   NSColor(red: 0xCE/255.0, green: 0xD4/255.0, blue: 0xDA/255.0, alpha: 1),
            angleDegrees: 135
        ),
    ]

    static let additionalPresets: [BeautifyPreset] = [
        gradient(
            id: "aurora",
            displayName: L10n.beautifyPresetAurora,
            startHex: 0xA8E6CF,
            endHex: 0x8B80F9
        ),
        gradient(
            id: "sunset-glow",
            displayName: L10n.beautifyPresetSunsetGlow,
            startHex: 0xFFB36B,
            endHex: 0xF26CA7
        ),
        gradient(
            id: "ocean-blue",
            displayName: L10n.beautifyPresetOceanBlue,
            startHex: 0x7FDBFF,
            endHex: 0x5B7CFA
        ),
        gradient(
            id: "lavender-mist",
            displayName: L10n.beautifyPresetLavenderMist,
            startHex: 0xD8C7FF,
            endHex: 0xF6C1E7
        ),
        gradient(
            id: "forest-mint",
            displayName: L10n.beautifyPresetForestMint,
            startHex: 0x6BCB9A,
            endHex: 0xD7F5C8
        ),
        gradient(
            id: "rose-gold",
            displayName: L10n.beautifyPresetRoseGold,
            startHex: 0xF6C1C7,
            endHex: 0xD9A66F
        ),
        gradient(
            id: "morning-sky",
            displayName: L10n.beautifyPresetMorningSky,
            startHex: 0xBEE9FF,
            endHex: 0xC8C4FF
        ),
        gradient(
            id: "candy-pop",
            displayName: L10n.beautifyPresetCandyPop,
            startHex: 0xFF9ECD,
            endHex: 0x9B8CFF
        ),
        gradient(
            id: "citrus-glow",
            displayName: L10n.beautifyPresetCitrusGlow,
            startHex: 0xFFE27A,
            endHex: 0xFF9F5A
        ),
        gradient(
            id: "midnight",
            displayName: L10n.beautifyPresetMidnight,
            startHex: 0x243B6B,
            endHex: 0x6B4FB3
        ),
        gradient(
            id: "coral-bloom",
            displayName: L10n.beautifyPresetCoralBloom,
            startHex: 0xFF8A7A,
            endHex: 0xFFC3A0
        ),
        gradient(
            id: "arctic-ice",
            displayName: L10n.beautifyPresetArcticIce,
            startHex: 0x9CECFB,
            endHex: 0x65C7F7
        ),
        gradient(
            id: "sage-cream",
            displayName: L10n.beautifyPresetSageCream,
            startHex: 0xB8D8BA,
            endHex: 0xF3E9C9
        ),
        gradient(
            id: "graphite",
            displayName: L10n.beautifyPresetGraphite,
            startHex: 0x53565F,
            endHex: 0x1F2430
        ),
    ]

    static var defaults: [BeautifyPreset] {
        primaryPresets + additionalPresets
    }

    static func preset(forID id: String?) -> BeautifyPreset? {
        guard let id else { return nil }
        return defaults.first(where: { $0.id == id })
    }

    static var defaultPreset: BeautifyPreset {
        preset(forID: Defaults.lastBeautifyPresetID) ?? primaryPresets[0]
    }

    static func toolbarPresets(preferredIDs: [String]) -> [BeautifyPreset] {
        let pinnedPresets = [transparent, wallpaper]
        let pinnedIDs = Set(pinnedPresets.map(\.id))
        var movablePresets: [BeautifyPreset] = []

        for id in preferredIDs + primaryPresets.map(\.id) {
            guard
                !pinnedIDs.contains(id),
                let preset = preset(forID: id),
                !movablePresets.contains(where: { $0.id == preset.id })
            else {
                continue
            }
            movablePresets.append(preset)
            if movablePresets.count == primaryPresets.count - pinnedPresets.count {
                break
            }
        }

        return pinnedPresets + movablePresets
    }

    static func promotedToolbarPresetIDs(
        selecting presetID: String,
        currentIDs: [String]
    ) -> [String] {
        let pinnedIDs = Set([transparent.id, wallpaper.id])
        let currentMovableIDs = toolbarPresets(preferredIDs: currentIDs)
            .map(\.id)
            .filter { !pinnedIDs.contains($0) }

        guard preset(forID: presetID) != nil, !pinnedIDs.contains(presetID) else {
            return currentMovableIDs
        }

        return Array(
            ([presetID] + currentMovableIDs.filter { $0 != presetID })
                .prefix(primaryPresets.count - pinnedIDs.count)
        )
    }

    static func pickerPresets(excluding toolbarPresets: [BeautifyPreset]) -> [BeautifyPreset] {
        let toolbarPresetIDs = Set(toolbarPresets.map(\.id))
        return defaults.filter { !toolbarPresetIDs.contains($0.id) }
    }

    private static func gradient(
        id: String,
        displayName: String,
        startHex: UInt32,
        endHex: UInt32,
        angleDegrees: CGFloat = 135
    ) -> BeautifyPreset {
        BeautifyPreset(
            id: id,
            displayName: displayName,
            startColor: color(hex: startHex),
            endColor: color(hex: endHex),
            angleDegrees: angleDegrees
        )
    }

    private static func color(hex: UInt32) -> NSColor {
        NSColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
