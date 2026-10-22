import AppKit
import ScreenCaptureKit

/// Fresh enumeration for one frozen capture session, shared by hover requests.
/// Unlike the display cache, this never reuses windows from an earlier session.
final class WindowCaptureSource: @unchecked Sendable {
    private let contentTask = Task.detached(priority: .userInitiated) {
        try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    }

    static func makeLoader() -> WindowImageLoader {
        let source = WindowCaptureSource()
        return { windowID, pointSize in
            let content = try await source.contentTask.value
            try Task.checkCancellation()
            // A window may appear between the CG and SCK enumerations. Refresh
            // on a miss rather than caching that absence for the whole session.
            return try await ScreenCapturer.captureWindowAsync(
                windowID: windowID,
                pointSize: pointSize,
                preparedContent: content.windows.contains { $0.windowID == windowID } ? content : nil
            )
        }
    }

    deinit { contentTask.cancel() }
}
