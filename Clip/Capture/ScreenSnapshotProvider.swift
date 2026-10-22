import CoreGraphics
import Foundation
import ScreenCaptureKit

struct ScreenSnapshotTarget: Sendable {
    let displayID: CGDirectDisplayID
    let bounds: CGRect
    let scale: CGFloat
}

enum ScreenSnapshotEvent: @unchecked Sendable {
    case image(displayID: CGDirectDisplayID, image: CGImage)
    case failure(displayID: CGDirectDisplayID, error: Error)
    case finished
}

typealias ScreenSnapshotCancellation = () -> Void

protocol ScreenSnapshotProviding {
    func prewarm()

    @discardableResult
    func capture(
        targets: [ScreenSnapshotTarget],
        eventHandler: @escaping (ScreenSnapshotEvent) -> Void
    ) -> ScreenSnapshotCancellation
}

final class ScreenSnapshotProvider: ScreenSnapshotProviding {
    static let shared = ScreenSnapshotProvider()

    private let contentCache = ScreenSnapshotContentCache()
    private let cacheEpoch = ScreenSnapshotCacheEpoch()

    private init() {}

    func prewarm() {
        let contentCache = contentCache
        let cacheEpoch = cacheEpoch.current
        Task.detached(priority: .utility) {
            do {
                _ = try await contentCache.captureContent(
                    requiredDisplayIDs: [],
                    cacheEpoch: cacheEpoch
                )
            } catch {}
        }
    }

    func invalidateAndPrewarm(displayIDs: Set<CGDirectDisplayID>) {
        let contentCache = contentCache
        let cacheEpoch = cacheEpoch.advance()
        Task.detached(priority: .utility) {
            do {
                _ = try await contentCache.captureContent(
                    requiredDisplayIDs: displayIDs,
                    cacheEpoch: cacheEpoch
                )
            } catch is CancellationError {
                return
            } catch {}
        }
    }

    @discardableResult
    func capture(
        targets: [ScreenSnapshotTarget],
        eventHandler: @escaping (ScreenSnapshotEvent) -> Void
    ) -> ScreenSnapshotCancellation {
        let delivery = ScreenSnapshotEventDelivery(eventHandler: eventHandler)
        let contentCache = contentCache
        let requiredDisplayIDs = Set(targets.map(\.displayID))
        let cacheEpoch = cacheEpoch.current

        let task = Task.detached(priority: .userInitiated) {
            guard !Task.isCancelled else { return }

            do {
                let content = try await contentCache.captureContent(
                    requiredDisplayIDs: requiredDisplayIDs,
                    cacheEpoch: cacheEpoch
                )
                guard !Task.isCancelled else { return }

                await withTaskGroup(of: ScreenSnapshotEvent.self) { group in
                    for target in targets {
                        group.addTask {
                            await Self.capture(
                                target: target,
                                content: content
                            )
                        }
                    }

                    for await event in group {
                        guard !Task.isCancelled else {
                            group.cancelAll()
                            return
                        }
                        delivery.send(event)
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                for target in targets {
                    delivery.send(.failure(displayID: target.displayID, error: error))
                }
            }

            guard !Task.isCancelled else { return }
            delivery.send(.finished)
        }

        return {
            delivery.cancel()
            task.cancel()
        }
    }

    private static func capture(
        target: ScreenSnapshotTarget,
        content: SCShareableContent
    ) async -> ScreenSnapshotEvent {
        guard target.bounds.width > 0,
              target.bounds.height > 0,
              target.scale > 0 else {
            return .failure(
                displayID: target.displayID,
                error: ScreenSnapshotProviderError.invalidTarget(displayID: target.displayID)
            )
        }

        guard let display = content.displays.first(where: { $0.displayID == target.displayID }) else {
            return .failure(
                displayID: target.displayID,
                error: ScreenSnapshotProviderError.displayNotFound(displayID: target.displayID)
            )
        }

        // Capture-only chrome opts out through NSWindow.sharingType = .none.
        // The selection overlay stays shareable so external recorders can see
        // it; its backdrop capture starts before the overlay is presented.
        // Do not exclude the whole capcap process here: Settings, pinned
        // images, menus and popovers are valid screenshot targets and must
        // remain in the frozen desktop image.
        let filter = SCContentFilter(display: display, excludingWindows: [])

        let configuration = Self.makeStreamConfiguration(for: target)

        do {
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
            return .image(displayID: target.displayID, image: image)
        } catch {
            return .failure(displayID: target.displayID, error: error)
        }
    }

    static func makeStreamConfiguration(
        for target: ScreenSnapshotTarget
    ) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.width = max(Int(ceil(target.bounds.width * target.scale)), 1)
        configuration.height = max(Int(ceil(target.bounds.height * target.scale)), 1)
        configuration.capturesAudio = false
        configuration.showsCursor = false
        configuration.captureResolution = .best
        // SCScreenshotManager also consults the single-window flag when
        // compositing a display on macOS 26. Set both explicitly, otherwise
        // native window shadows disappear from region screenshots (#167)
        configuration.ignoreShadowsDisplay = false
        configuration.ignoreShadowsSingleWindow = false
        // SCScreenshotManager needs one frame. Keeping the stream default here
        // leaves multiple full-resolution IOSurfaces resident after a 5K
        // capture even though no subsequent frame can be consumed.
        configuration.queueDepth = 1
        return configuration
    }
}

private final class ScreenSnapshotCacheEpoch: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var current: Int {
        lock.withLock { value }
    }

    func advance() -> Int {
        lock.withLock {
            value += 1
            return value
        }
    }
}

private actor ScreenSnapshotContentCache {
    private struct ContentLoad {
        let id: UUID
        let task: Task<SCShareableContent, Error>
    }

    private var cachedContent: SCShareableContent?
    private var loading: ContentLoad?
    private var activeEpoch = 0

    func captureContent(
        requiredDisplayIDs: Set<CGDirectDisplayID>,
        cacheEpoch: Int
    ) async throws -> SCShareableContent {
        synchronize(to: cacheEpoch)
        let content = try await displayContent(
            requiredDisplayIDs: requiredDisplayIDs,
            cacheEpoch: cacheEpoch
        )
        try validate(cacheEpoch)
        return content
    }

    private func displayContent(
        requiredDisplayIDs: Set<CGDirectDisplayID>,
        cacheEpoch: Int
    ) async throws -> SCShareableContent {
        try validate(cacheEpoch)
        if let cachedContent,
           isSuitable(
               cachedContent,
               requiredDisplayIDs: requiredDisplayIDs
           ) {
            return cachedContent
        }
        var content = try await loadFreshContent()
        try validate(cacheEpoch)
        if !isSuitable(
            content,
            requiredDisplayIDs: requiredDisplayIDs
        ) {
            cachedContent = nil
            content = try await loadFreshContent()
            try validate(cacheEpoch)
        }
        cachedContent = content
        return content
    }

    private func loadFreshContent() async throws -> SCShareableContent {
        if let loading {
            return try await loading.task.value
        }

        let id = UUID()
        let task = Task.detached(priority: .userInitiated) {
            try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
        }
        loading = ContentLoad(id: id, task: task)

        do {
            let content = try await task.value
            if loading?.id == id {
                loading = nil
            }
            return content
        } catch {
            if loading?.id == id {
                loading = nil
            }
            throw error
        }
    }

    private func synchronize(to cacheEpoch: Int) {
        guard cacheEpoch > activeEpoch else { return }
        activeEpoch = cacheEpoch
        cachedContent = nil
        loading?.task.cancel()
        loading = nil
    }

    private func validate(_ cacheEpoch: Int) throws {
        guard cacheEpoch == activeEpoch else {
            throw CancellationError()
        }
    }

    private func isSuitable(
        _ content: SCShareableContent,
        requiredDisplayIDs: Set<CGDirectDisplayID>
    ) -> Bool {
        let displayIDs = Set(content.displays.map(\.displayID))
        return requiredDisplayIDs.isSubset(of: displayIDs)
    }
}

private final class ScreenSnapshotEventDelivery: @unchecked Sendable {
    private let lock = NSRecursiveLock()
    private var eventHandler: ((ScreenSnapshotEvent) -> Void)?
    private var isCancelled = false

    init(eventHandler: @escaping (ScreenSnapshotEvent) -> Void) {
        self.eventHandler = eventHandler
    }

    func send(_ event: ScreenSnapshotEvent) {
        lock.lock()
        defer { lock.unlock() }
        guard !isCancelled else { return }
        eventHandler?(event)
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        isCancelled = true
        eventHandler = nil
    }
}

private enum ScreenSnapshotProviderError: LocalizedError {
    case invalidTarget(displayID: CGDirectDisplayID)
    case displayNotFound(displayID: CGDirectDisplayID)

    var errorDescription: String? {
        switch self {
        case let .invalidTarget(displayID):
            return "Invalid screen snapshot target for display \(displayID)"
        case let .displayNotFound(displayID):
            return "ScreenCaptureKit display \(displayID) was not found"
        }
    }
}
