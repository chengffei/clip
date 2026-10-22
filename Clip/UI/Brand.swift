import AppKit

/// Clip's visual identity: ink surfaces, one acid accent, one alert tone,
/// square-ish geometry and monospaced labels. Every chrome surface reads
/// from here so the look can be tuned in one place.
enum Brand {
    // Surfaces
    static let ink = NSColor(srgbRed: 0.055, green: 0.055, blue: 0.067, alpha: 1)        // #0E0E11
    static let inkRaised = NSColor(srgbRed: 0.102, green: 0.102, blue: 0.122, alpha: 1)  // #1A1A1F
    static let inkFloating = NSColor(srgbRed: 0.055, green: 0.055, blue: 0.067, alpha: 0.94)

    // Lines and fills
    static let line = NSColor.white.withAlphaComponent(0.14)
    static let lineStrong = NSColor.white.withAlphaComponent(0.26)
    static let subtleFill = NSColor.white.withAlphaComponent(0.08)

    // Text
    static let text = NSColor(srgbRed: 0.949, green: 0.949, blue: 0.941, alpha: 1)       // #F2F2F0
    static let muted = NSColor(srgbRed: 0.541, green: 0.541, blue: 0.576, alpha: 1)      // #8A8A93

    // Accents
    static let accent = NSColor(srgbRed: 0.80, green: 1.0, blue: 0.0, alpha: 1)          // #CCFF00 acid
    static let accentFill = NSColor(srgbRed: 0.80, green: 1.0, blue: 0.0, alpha: 0.18)
    static let alert = NSColor(srgbRed: 1.0, green: 0.302, blue: 0.180, alpha: 1)        // #FF4D2E coral
    static let onAccent = ink

    // Geometry
    static let radius: CGFloat = 4
    static let radiusLarge: CGFloat = 6
    static let hairline: CGFloat = 1

    // Type
    static func mono(_ size: CGFloat, weight: NSFont.Weight = .medium) -> NSFont {
        .monospacedSystemFont(ofSize: size, weight: weight)
    }

    static func label(_ size: CGFloat, weight: NSFont.Weight = .semibold) -> NSFont {
        .systemFont(ofSize: size, weight: weight)
    }
}
