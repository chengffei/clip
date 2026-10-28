import AppKit

/// Clip's visual identity: Apple-style light chrome. White floating surfaces
/// with a hairline and a soft shadow, near-black text, one blue accent used
/// only for selection geometry and the primary action, one red for alerts.
/// Every chrome surface reads from here so the look can be tuned in one place.
enum Brand {
    // Surfaces
    static let surface = NSColor.white                                                      // #FFFFFF
    static let surfaceRaised = NSColor.white                                                // cards on canvas
    static let canvas = NSColor(srgbRed: 0.961, green: 0.961, blue: 0.969, alpha: 1)        // #F5F5F7
    static let sidebar = NSColor(srgbRed: 0.941, green: 0.941, blue: 0.953, alpha: 1)       // #F0F0F3
    static let floating = NSColor(white: 1, alpha: 0.98)

    // Lines and fills
    static let line = NSColor.black.withAlphaComponent(0.08)
    static let lineStrong = NSColor.black.withAlphaComponent(0.14)
    static let subtleFill = NSColor.black.withAlphaComponent(0.05)
    static let selectedFill = NSColor.black.withAlphaComponent(0.08)

    // Text
    static let text = NSColor(srgbRed: 0.114, green: 0.114, blue: 0.122, alpha: 1)          // #1D1D1F
    static let muted = NSColor(srgbRed: 0.431, green: 0.431, blue: 0.451, alpha: 1)         // #6E6E73

    // Accents
    static let accent = NSColor(srgbRed: 0.0, green: 0.478, blue: 1.0, alpha: 1)            // #007AFF
    static let accentFill = NSColor(srgbRed: 0.0, green: 0.478, blue: 1.0, alpha: 0.14)
    static let alert = NSColor(srgbRed: 1.0, green: 0.231, blue: 0.188, alpha: 1)           // #FF3B30
    static let onAccent = NSColor.white

    // Selection geometry (capture overlay and editor frame)
    static let selectionStroke: CGFloat = 2
    static let handleDiameter: CGFloat = 9
    static let handleRing: CGFloat = 1.5
    static let labelBackground = NSColor(srgbRed: 0.114, green: 0.114, blue: 0.122, alpha: 0.82)
    static let onLabel = NSColor.white

    // Geometry
    static let radius: CGFloat = 6
    static let radiusLarge: CGFloat = 10
    static let hairline: CGFloat = 1

    // Shadow for floating chrome
    static let shadowOpacity: Float = 0.18
    static let shadowRadius: CGFloat = 12
    static let shadowOffset = CGSize(width: 0, height: -3)

    // Type
    static func mono(_ size: CGFloat, weight: NSFont.Weight = .medium) -> NSFont {
        .monospacedSystemFont(ofSize: size, weight: weight)
    }

}
