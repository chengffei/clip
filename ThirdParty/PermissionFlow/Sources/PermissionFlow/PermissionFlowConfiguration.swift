#if os(macOS)
import AppKit
import Foundation

@available(macOS 13.0, *)
public struct PermissionFlowConfiguration: Sendable {
    /// Apps that should already appear in the floating panel.
    public var requiredAppURLs: [URL]

    /// Optional locale identifier injected into the floating panel's SwiftUI
    /// environment to override localization.
    public var localeIdentifier: String?

    public init(
        requiredAppURLs: [URL] = [],
        localeIdentifier: String? = nil
    ) {
        self.requiredAppURLs = requiredAppURLs
        self.localeIdentifier = localeIdentifier
    }
}
#endif
