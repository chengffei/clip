import AppKit
import os.log

/// Detects the double-tap ⌘ trigger.
///
/// Two capture paths:
/// 1. A listen-only CGEvent tap (lowest latency, also sees events while another
///    app has secure input). It only delivers events when the process has
///    Input Monitoring access, which Accessibility-trusted apps get implicitly.
/// 2. NSEvent global + local monitors (needs Accessibility only).
///
/// We pick the tap only when `CGPreflightListenEventAccess()` confirms the
/// session will actually deliver events to it; otherwise a tap can be created
/// successfully and then stay silent forever, which is what "double-tap ⌘ does
/// nothing" looks like from the outside. Every decision is logged under the
/// `com.chengffei.clip` subsystem so it can be read with `log stream`.
class KeyMonitor {
    private static let log = Logger(subsystem: "com.chengffei.clip", category: "KeyMonitor")

    /// Master switch. When false, neither trigger fires (used during shortcut recording).
    var isEnabled: Bool = true {
        didSet {
            if !isEnabled { resetSequence() }
        }
    }

    /// Plain double-tap ⌘ → regular screenshot. Disabled when a custom hotkey is registered.
    var isRegularDoubleTapEnabled: Bool = true {
        didSet { if !isRegularDoubleTapEnabled { resetSequence() } }
    }

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var keyDownMonitor: Any?
    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?
    /// Start of the current (or last) ⌘ press.
    private var commandDownTime: TimeInterval = 0
    /// Start of the previous press, restored when a release turns out to be
    /// switch bounce.
    private var previousCommandDownTime: TimeInterval = 0
    private var lastCommandUpTime: TimeInterval = 0
    /// Press time of the last clean tap, the first half of a double tap.
    /// Zero when the last ⌘ release did not qualify.
    private var tapDownTime: TimeInterval = 0
    private var commandIsDown = false
    private var otherKeyPressed = false

    /// A tap is a ⌘ press released within this time with no other input
    /// (Karabiner's to_if_alone and QMK's tapping term use the same rule).
    /// Holding ⌘ longer, for a shortcut you then abandon, never counts.
    static let maxTapHold: TimeInterval = 0.2
    /// A release and re-press closer than this is switch bounce while ⌘ is
    /// held, not a second tap: people cannot release and press in 30 ms.
    static let bounceInterval: TimeInterval = 0.03
    private let onTrigger: (CaptureTriggerContext) -> Void
    /// A lone ⌘ tap was released quickly enough to be the first half of a
    /// double-tap. Lets the snapshot start before the second tap lands.
    var onFirstTapReleased: (() -> Void)?

    struct ModifierSample {
        let commandIsDown: Bool
        let hasDisruptiveModifiers: Bool
        let eventUptime: TimeInterval
    }

    init(onTrigger: @escaping (CaptureTriggerContext) -> Void, monitoring: Bool = true) {
        self.onTrigger = onTrigger
        if monitoring { startMonitoring() }
    }

    deinit {
        stopMonitoring()
    }


    private func startMonitoring() {
        let axTrusted = AXIsProcessTrusted()
        let listenAccess = CGPreflightListenEventAccess()
        Self.log.notice("start: accessibility=\(axTrusted) inputMonitoring=\(listenAccess)")
        FileLog.write("KeyMonitor start accessibility=\(axTrusted) inputMonitoring=\(listenAccess)")

        if listenAccess, startEventTapMonitoring() {
            Self.log.notice("path: CGEvent tap")
            FileLog.write("KeyMonitor path=event-tap")
            return
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }
        keyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel, .magnify, .rotate, .swipe, .gesture]) { [weak self] event in
            switch event.type {
            case .scrollWheel, .magnify, .rotate, .swipe, .gesture:
                self?.notePointerGesture()
                return
            default:
                break
            }
            self?.otherKeyPressed = true
        }
        Self.log.notice("path: NSEvent monitors, accessibility=\(axTrusted)")
        FileLog.write("KeyMonitor path=nsevent-monitor accessibility=\(axTrusted)")
    }

    private func stopMonitoring() {
        if let source = eventTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            eventTapSource = nil
        }
        if let tap = eventTap {
            CFMachPortInvalidate(tap)
            eventTap = nil
        }
        if let m = globalMonitor {
            NSEvent.removeMonitor(m)
            globalMonitor = nil
        }
        if let m = localMonitor {
            NSEvent.removeMonitor(m)
            localMonitor = nil
        }
        if let m = keyDownMonitor {
            NSEvent.removeMonitor(m)
            keyDownMonitor = nil
        }
    }

    private func resetSequence() {
        tapDownTime = 0
        commandDownTime = 0
        previousCommandDownTime = 0
        lastCommandUpTime = 0
        commandIsDown = false
        otherKeyPressed = false
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        handleModifierSample(ModifierSample(
            commandIsDown: event.modifierFlags.contains(.command),
            hasDisruptiveModifiers: event.modifierFlags.contains(.shift)
                || event.modifierFlags.contains(.control)
                || event.modifierFlags.contains(.option),
            eventUptime: event.timestamp
        ))
    }

    @discardableResult
    private func startEventTapMonitoring() -> Bool {
        // Mouse downs count as "another key": ⌘-click (multi-select, open in new tab) is not a ⌘ tap.
        // Without them two quick ⌘-clicks read as a double tap, and every ⌘-click started a
        // speculative full-screen snapshot.
        // Scrolls and trackpad gestures count only while ⌘ is held (⌘-scroll zoom,
        // pinch): momentum scrolling right before a real double tap must not block it.
        let types: [CGEventType] = [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
            | Self.gestureEventTypes.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1) }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<KeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
                monitor.handleTappedEvent(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Self.log.error("CGEvent.tapCreate returned nil")
            FileLog.write("KeyMonitor tapCreate=nil")
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        eventTapSource = source
        return true
    }

    private func handleTappedEvent(type: CGEventType, event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            Self.log.error("event tap disabled (\(type.rawValue)), re-enabling")
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
        case .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown:
            otherKeyPressed = true
        case .scrollWheel:
            notePointerGesture()
        case .flagsChanged:
            let flags = event.flags
            handleModifierSample(ModifierSample(
                commandIsDown: flags.contains(.maskCommand),
                hasDisruptiveModifiers: flags.contains(.maskShift)
                    || flags.contains(.maskControl)
                    || flags.contains(.maskAlternate),
                eventUptime: Double(event.timestamp) / 1_000_000_000
            ))
        default:
            if Self.gestureEventTypes.contains(UInt64(type.rawValue)) {
                notePointerGesture()
            }
        }
    }

    /// NSEvent raw types for trackpad gestures (rotate 18, gesture 29,
    /// magnify 30, swipe 31, smartMagnify 32); CGEventType has no names for them.
    private static let gestureEventTypes: [UInt64] = [18, 29, 30, 31, 32]

    /// A scroll or trackpad gesture made while ⌘ is held breaks the tap.
    func notePointerGesture() {
        if commandIsDown { otherKeyPressed = true }
    }

    /// Test hook: a mouse button went down (the event tap and the fallback monitors do the same).
    func noteMouseDown() { otherKeyPressed = true }

    func handleModifierSample(_ sample: ModifierSample) {
        guard isEnabled else { return }

        if sample.hasDisruptiveModifiers {
            otherKeyPressed = true
            tapDownTime = 0
            commandIsDown = sample.commandIsDown
            return
        }

        let now = sample.eventUptime
        if sample.commandIsDown && !commandIsDown {
            commandIsDown = true
            if lastCommandUpTime > 0, now - lastCommandUpTime < Self.bounceInterval {
                // Bounce: the key never really came up. Continue the earlier
                // press, which also voids the tap its false release created.
                commandDownTime = previousCommandDownTime
                tapDownTime = 0
                FileLog.write("⌘ bounce gap=\(Self.ms(now - lastCommandUpTime))ms ignored")
                return
            }
            let firstTapIsClean = tapDownTime > 0 && !otherKeyPressed
            let withinWindow = tapDownTime > 0 && now - tapDownTime < Defaults.doubleTapInterval
            let isDoubleTap = firstTapIsClean && withinWindow
            Self.log.debug("⌘ down: tap=\(self.tapDownTime > 0) withinWindow=\(withinWindow) otherKey=\(self.otherKeyPressed) double=\(isDoubleTap)")
            FileLog.write("⌘ down tap=\(tapDownTime > 0) withinWindow=\(withinWindow) otherKey=\(otherKeyPressed) double=\(isDoubleTap) regularEnabled=\(isRegularDoubleTapEnabled)")

            if isDoubleTap, isRegularDoubleTapEnabled {
                let context = CaptureTriggerContext(
                    source: .doubleCommand,
                    eventUptime: now
                )
                context.mark(.doubleCommandDetected)
                MainRunLoopScheduler.perform { [weak self] in
                    context.mark(.mainRunLoopCallback)
                    guard let self else {
                        context.finish(.ignored)
                        return
                    }
                    self.onTrigger(context)
                }
            }
            tapDownTime = 0
            previousCommandDownTime = commandDownTime
            commandDownTime = now
            otherKeyPressed = false
            return
        }

        if !sample.commandIsDown && commandIsDown {
            commandIsDown = false
            lastCommandUpTime = now
            let hold = now - commandDownTime
            let isTap = commandDownTime > 0 && !otherKeyPressed && hold <= Self.maxTapHold
            tapDownTime = isTap ? commandDownTime : 0
            FileLog.write("⌘ up hold=\(Self.ms(hold))ms otherKey=\(otherKeyPressed) tap=\(isTap)")
            if isTap, isRegularDoubleTapEnabled, let onFirstTapReleased {
                onFirstTapReleased()
            }
            otherKeyPressed = false
            return
        }

        commandIsDown = sample.commandIsDown
    }

    private static func ms(_ seconds: TimeInterval) -> Int {
        Int((seconds * 1000).rounded())
    }
}
