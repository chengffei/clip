import AppKit
import AVFoundation

enum AppPermissions {
    static var allRequiredGranted: Bool {
        accessibilityGranted && screenRecordingGranted
    }

    static var accessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    static var screenRecordingGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Optional permission — NOT part of `allRequiredGranted`. Synchronous,
    /// non-prompting check.
    static var microphoneGranted: Bool {
        AVAudioApplication.shared.recordPermission == .granted
    }

    /// True once the user explicitly denied access (macOS then ignores
    /// re-prompts, so we deep-link to System Settings instead).
    static var microphoneDenied: Bool {
        AVAudioApplication.shared.recordPermission == .denied
    }

    /// Async-prompt for mic permission; completion on the main actor. macOS
    /// shows the prompt once — later calls just report the current state.
    static func requestMicrophonePermission(completion: @escaping @MainActor (Bool) -> Void) {
        AVAudioApplication.requestRecordPermission { granted in
            Task { @MainActor in
                completion(granted)
            }
        }
    }
}
