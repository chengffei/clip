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

/// No-op compatibility surface retained so trigger plumbing stays unchanged.
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

    init(
        sessionID _: UUID,
        source _: CaptureTriggerContext.Source,
        eventUptime _: TimeInterval
    ) {}

    func mark(_: Stage) {}

    func finish(_: Outcome) {}
}
