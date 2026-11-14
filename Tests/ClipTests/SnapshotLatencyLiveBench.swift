import AppKit
import ScreenCaptureKit
import XCTest
@testable import Clip

/// Real ScreenCaptureKit timings for the frozen-desktop snapshot, the stage
/// that dominates double-tap ⌘ latency in clip.log. Needs Screen Recording
/// permission for the test host:
/// `CLIP_SNAPSHOT_BENCH=1 swift test -c release -Xswiftc -enable-testing --filter SnapshotLatencyLiveBench`
/// `CLIP_SNAPSHOT_IDLE` sets the idle gaps in seconds (default "0.5,3,15").
final class SnapshotLatencyLiveBench: XCTestCase {
    private var enabled: Bool { ProcessInfo.processInfo.environment["CLIP_SNAPSHOT_BENCH"] != nil }

    private var idleGaps: [Double] {
        (ProcessInfo.processInfo.environment["CLIP_SNAPSHOT_IDLE"] ?? "0.5,3,15")
            .split(separator: ",").compactMap { Double($0) }
    }

    private var rounds: Int {
        Int(ProcessInfo.processInfo.environment["CLIP_SNAPSHOT_ROUNDS"] ?? "") ?? 5
    }

    private static func mainTarget() throws -> ScreenSnapshotTarget {
        let screen = try XCTUnwrap(NSScreen.main)
        let displayID = try XCTUnwrap(
            screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        )
        return ScreenSnapshotTarget(
            displayID: displayID,
            bounds: CGDisplayBounds(displayID),
            scale: screen.backingScaleFactor
        )
    }

    /// One snapshot through the production provider; returns ms and the image.
    private static func providerCapture(_ target: ScreenSnapshotTarget) async -> (Double, CGImage?) {
        let start = DispatchTime.now().uptimeNanoseconds
        let image: CGImage? = await withCheckedContinuation { continuation in
            let box = OnceBox<CGImage?>(continuation)
            ScreenSnapshotProvider.shared.capture(targets: [target]) { event in
                switch event {
                case .image(_, let image): box.resume(image)
                case .failure: box.resume(nil)
                case .finished: box.resume(nil)
                }
            }
        }
        return (Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6, image)
    }

    private static func median(_ xs: [Double]) -> Double {
        let s = xs.sorted()
        return s.isEmpty ? .nan : s[s.count / 2]
    }

    private static func fmt(_ xs: [Double]) -> String {
        let s = xs.sorted()
        guard !s.isEmpty else { return "n=0" }
        return String(format: "n=%d min=%.0f p50=%.0f max=%.0f  [%@]", s.count, s.first!, median(s), s.last!,
                      xs.map { String(format: "%.0f", $0) }.joined(separator: " "))
    }

    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : .nan
    }

    static func cpuMS() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) * 1000
            + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1000
    }

    /// Run once per mode, each in a fresh process: CLIP_COLD_WARM=none|prewarm.
    func testColdStartPrewarm() async throws {
        guard enabled, let raw = ProcessInfo.processInfo.environment["CLIP_COLD_WARM"] else { return }
        let target = try Self.mainTarget()
        if raw == "prewarm" {
            await ScreenSnapshotProvider.shared.prewarm().value
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        let (first, _) = await Self.providerCapture(target)
        let (second, _) = await Self.providerCapture(target)
        print(String(format: "SNAPBENCH cold %@ first=%.0fms second=%.0fms", raw, first, second))
    }

    /// A speculative snapshot started 150ms before the request (the gap
    /// between a lone first ⌘ release and the second ⌘ press).
    func testSpeculativeSnapshot() async throws {
        guard enabled else { return }
        let target = try Self.mainTarget()
        _ = await Self.providerCapture(target)
        var plain: [Double] = []
        var speculative: [Double] = []
        for _ in 0..<rounds {
            try await Task.sleep(nanoseconds: 2_000_000_000)
            plain.append(await Self.providerCapture(target).0)
            try await Task.sleep(nanoseconds: 2_000_000_000)
            ScreenSnapshotProvider.shared.beginSpeculativeCapture(targets: [target], lifetime: 0.55)
            try await Task.sleep(nanoseconds: 80_000_000)
            speculative.append(await Self.providerCapture(target).0)
        }
        // Expired speculation must not be reused.
        ScreenSnapshotProvider.shared.beginSpeculativeCapture(targets: [target], lifetime: 0.2)
        try await Task.sleep(nanoseconds: 400_000_000)
        let expired = await Self.providerCapture(target).0
        print("SNAPBENCH speculative plain       \(Self.fmt(plain))")
        print("SNAPBENCH speculative 80ms ahead  \(Self.fmt(speculative))")
        print(String(format: "SNAPBENCH speculative expired -> fresh capture %.0fms", expired))
    }

    /// Leak check target: prewarm, speculative (used and discarded) and
    /// plain snapshots, then waits so `leaks <pid>` can inspect the process.
    /// `CLIP_SNAPSHOT_BENCH=1 CLIP_LEAK_PAUSE=30 MallocStackLogging=lite swift test ...`
    func testLeakCheckPause() async throws {
        guard enabled, let pause = Double(ProcessInfo.processInfo.environment["CLIP_LEAK_PAUSE"] ?? "") else { return }
        let target = try Self.mainTarget()
        await ScreenSnapshotProvider.shared.prewarm().value
        for _ in 0..<8 {
            _ = await Self.providerCapture(target)
            ScreenSnapshotProvider.shared.beginSpeculativeCapture(targets: [target], lifetime: 0.5)
            try await Task.sleep(nanoseconds: 100_000_000)
            _ = await Self.providerCapture(target)
            ScreenSnapshotProvider.shared.beginSpeculativeCapture(targets: [target], lifetime: 0.3)
            try await Task.sleep(nanoseconds: 600_000_000)
        }
        print("SNAPBENCH leak-check pid=\(getpid()) pausing \(pause)s")
        fflush(stdout)
        try await Task.sleep(nanoseconds: UInt64(pause * 1e9))
    }

    /// What a discarded speculative snapshot costs this process.
    func testDiscardedSnapshotCost() async throws {
        guard enabled else { return }
        let target = try Self.mainTarget()
        _ = await Self.providerCapture(target)
        try await Task.sleep(nanoseconds: 1_000_000_000)
        let footprintBefore = Self.footprintMB()
        let cpuBefore = Self.cpuMS()
        let n = 20
        var peak = footprintBefore
        for _ in 0..<n {
            autoreleasepool {}
            let (_, image) = await Self.providerCapture(target)
            peak = max(peak, Self.footprintMB())
            _ = image?.width
            try await Task.sleep(nanoseconds: 300_000_000)
        }
        try await Task.sleep(nanoseconds: 1_000_000_000)
        print(String(format: "SNAPBENCH discard-cost cpu/capture=%.1fms footprint before=%.0fMB peak=%.0fMB after=%.0fMB",
                     (Self.cpuMS() - cpuBefore) / Double(n), footprintBefore, peak, Self.footprintMB()))
    }

    func testSnapshotLatencyByIdleGap() async throws {
        guard enabled else { return }
        let target = try Self.mainTarget()
        // First call ever in this process: SCShareableContent + daemon cold.
        let (first, firstImage) = await Self.providerCapture(target)
        let image = try XCTUnwrap(firstImage, "no Screen Recording permission for the test host?")
        print(String(format: "SNAPBENCH first-in-process %.0fms %dx%d space=%@ bpc=%d alpha=%d", first,
                     image.width, image.height,
                     (image.colorSpace?.name as String?) ?? "nil", image.bitsPerComponent,
                     image.alphaInfo.rawValue))

        for gap in idleGaps {
            var plain: [Double] = []
            for _ in 0..<rounds {
                try await Task.sleep(nanoseconds: UInt64(gap * 1e9))
                plain.append(await Self.providerCapture(target).0)
            }
            print("SNAPBENCH gap=\(gap)s plain  \(Self.fmt(plain))")
        }
    }
}

private final class OnceBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Never>?
    init(_ continuation: CheckedContinuation<T, Never>) { self.continuation = continuation }
    func resume(_ value: T) {
        lock.lock()
        let c = continuation
        continuation = nil
        lock.unlock()
        c?.resume(returning: value)
    }
}
