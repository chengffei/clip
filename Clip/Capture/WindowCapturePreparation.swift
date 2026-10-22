import AppKit

/// One document's pending silhouette. Drafts retain this object across editor
/// teardown; observers belong to individual editors and are removed on detach.
/// State and observers are accessed on the main run loop only. Pixel work runs
/// on the worker, and never reads editor state or replaces frozen RGB pixels.
final class WindowCapturePreparation {
    private(set) var image: NSImage?
    private(set) var isComplete = false
    private var observers: [UUID: (NSImage) -> Void] = [:]
    private var task: Task<Void, Never>?
    private let captureTask: Task<NSImage?, Never>

    init(
        snapshotImage: NSImage,
        captureRect: CGRect,
        displayBounds: CGRect,
        captureTask: Task<NSImage?, Never>
    ) {
        self.captureTask = captureTask
        task = Task.detached(priority: .userInitiated) { [weak self] in
            let directImage = await captureTask.value
            guard !Task.isCancelled else { return }
            let usableImage = directImage.flatMap {
                // A resized live window cannot supply a silhouette for the
                // frozen document. Allow only the APIs' sub-point rounding.
                abs($0.size.width - snapshotImage.size.width) <= 1
                    && abs($0.size.height - snapshotImage.size.height) <= 1
                    && !ScreenCapturer.isEffectivelyTransparent($0) ? $0 : nil
            }
            let image = WindowEffects.compositedWindowImage(
                snapshotImage: snapshotImage,
                directWindowImage: usableImage,
                captureRect: captureRect,
                displayBounds: displayBounds
            )
            guard !Task.isCancelled else { return }
            MainRunLoopScheduler.perform { [weak self] in
                guard let self else { return }
                self.image = image
                self.isComplete = true
                self.task = nil
                let callbacks = Array(self.observers.values)
                self.observers.removeAll()
                callbacks.forEach { $0(image) }
            }
        }
    }

    func observe(_ callback: @escaping (NSImage) -> Void) -> UUID {
        let id = UUID()
        if let image { callback(image) }
        else { observers[id] = callback }
        return id
    }

    func removeObserver(_ id: UUID) {
        observers.removeValue(forKey: id)
    }

    deinit {
        task?.cancel()
        captureTask.cancel()
    }

    static func capture(
        windowID: CGWindowID,
        pointSize: NSSize,
        timeout: TimeInterval,
        loader: @escaping WindowImageLoader,
        debounce: Bool = false
    ) -> Task<NSImage?, Never> {
        Task.detached(priority: .userInitiated) {
            do {
                if debounce { try await Task.sleep(nanoseconds: 80_000_000) }
                try Task.checkCancellation()
                return try await AsyncDeadline.run(seconds: timeout) {
                    try await loader(windowID, pointSize)
                }
            } catch { return nil }
        }
    }
}
