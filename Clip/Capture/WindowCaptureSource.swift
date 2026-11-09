import AppKit
import ScreenCaptureKit

/// Fresh enumeration for one frozen capture session, shared by hover requests.
/// Unlike the display cache, this never reuses windows from an earlier session.
final class WindowCaptureSource: @unchecked Sendable {
    private let lock = NSLock()
    private var startedContentTask: Task<SCShareableContent, Error>?

    /// Started on the first window request, not when the overlay session is
    /// created: an eager enumeration ran alongside the frozen snapshot and
    /// the window list during the latency-critical first frames, and most
    /// sessions never ask for a window image.
    private var contentTask: Task<SCShareableContent, Error> {
        lock.withLock {
            if let startedContentTask { return startedContentTask }
            let task = Task.detached(priority: .userInitiated) {
                try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            }
            startedContentTask = task
            return task
        }
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

    deinit { startedContentTask?.cancel() }
}
