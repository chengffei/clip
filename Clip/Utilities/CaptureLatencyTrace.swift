import Foundation

/// Preserves the screenshot trigger API used across asynchronous capture paths.
struct CaptureTriggerContext: @unchecked Sendable {
    enum Source: String, Sendable {
        case keyboardShortcut = "keyboard-shortcut"
        case doubleCommand = "double-command"
        case menu
        case countdown
        case programmatic
    }

    let trace: CaptureLatencyTrace

    init(
        source: Source,
        eventUptime: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) {
        self.trace = CaptureLatencyTrace(
            sessionID: UUID(),
            source: source,
            eventUptime: eventUptime
        )
    }

    func mark(_ stage: CaptureLatencyTrace.Stage) {
        trace.mark(stage)
    }

    func finish(_ outcome: CaptureLatencyTrace.Outcome) {
        trace.finish(outcome)
    }
}

/// Times each capture from the key event to the first overlay frame and
/// writes one line to clip.log when it finishes, e.g.
/// `capture latency double-command presented total=48ms startCapture=3 …`.
/// Stages reached after that (the frozen snapshot usually) get a second line.
final class CaptureLatencyTrace: @unchecked Sendable {
    enum Stage: String, Sendable {
        case carbonEventReceived = "carbon-event-received"
        case doubleCommandDetected = "double-command-detected"
        case mainRunLoopCallback = "main-run-loop-callback"
        case handleTrigger = "handle-trigger"
        case startCapture = "start-capture"
        case overlayInitialized = "overlay-initialized"
        case activateRequested = "activate-requested"
        case backgroundPreparationStarted = "background-preparation-started"
        case windowEnumerationReady = "window-enumeration-ready"
        case windowEnumerationApplied = "window-enumeration-applied"
        case snapshotCaptureStarted = "snapshot-capture-started"
        case snapshotResultReady = "snapshot-result-ready"
        case snapshotResultApplied = "snapshot-result-applied"
        case overlayOrderedFront = "overlay-ordered-front"
        case firstDrawCompleted = "first-draw-completed"
        case firstFrame = "first-frame"
    }

    enum Outcome: String, Sendable {
        case presented
        case cancelled
        case superseded
        case failed
        case ignored
        case rerouted
    }

    private let source: CaptureTriggerContext.Source
    private let eventUptime: TimeInterval
    private let lock = NSLock()
    private var marks: [(Stage, Int)] = []
    private var finished = false

    init(
        sessionID _: UUID,
        source: CaptureTriggerContext.Source,
        eventUptime: TimeInterval
    ) {
        self.source = source
        let now = ProcessInfo.processInfo.systemUptime
        // Event timestamps from some paths are not on the uptime clock; fall
        // back to now rather than log nonsense.
        self.eventUptime = (eventUptime > 0 && eventUptime <= now && now - eventUptime < 5) ? eventUptime : now
    }

    private func elapsedMS() -> Int {
        Int(((ProcessInfo.processInfo.systemUptime - eventUptime) * 1000).rounded())
    }

    func mark(_ stage: Stage) {
        let ms = elapsedMS()
        lock.lock()
        let seen = marks.contains { $0.0 == stage }
        if !seen { marks.append((stage, ms)) }
        let late = finished && !seen
        lock.unlock()
        if late { FileLog.write("capture latency \(source.rawValue) late \(stage.rawValue)=\(ms)ms") }
    }

    func finish(_ outcome: Outcome) {
        let ms = elapsedMS()
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let stages = marks.map { "\($0.0.rawValue)=\($0.1)" }.joined(separator: " ")
        lock.unlock()
        guard outcome != .ignored, outcome != .rerouted else { return }
        FileLog.write("capture latency \(source.rawValue) \(outcome.rawValue) total=\(ms)ms \(stages)")
    }
}
