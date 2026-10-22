import Foundation

/// A deadline for system APIs which may never finish, even after cancellation.
/// A task group cannot provide this guarantee: leaving its scope waits for all
/// children. Late results here are discarded, and the caller resumes once only.
enum AsyncDeadline {
    struct TimedOut: Error {}

    private static let timerQueue = DispatchQueue(
        label: "capcap.async-deadline", qos: .userInitiated, attributes: .concurrent
    )

    static func run<Value>(
        seconds: TimeInterval,
        operation: @escaping () async throws -> Value
    ) async throws -> Value {
        let state = State<Value>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                state.install(continuation)
                let worker = Task.detached {
                    do { state.finish(.success(try await operation())) }
                    catch { state.finish(.failure(error)) }
                }
                // Keep the deadline independent of the cooperative executor:
                // a blocked system call must not also prevent its timeout.
                let timer = DispatchSource.makeTimerSource(queue: timerQueue)
                timer.schedule(deadline: .now() + max(0, seconds))
                timer.setEventHandler {
                    state.finish(.failure(TimedOut()))
                }
                timer.resume()
                state.install(worker: worker, timer: timer)
            }
        } onCancel: {
            state.finish(.failure(CancellationError()))
        }
    }

    private final class State<Value>: @unchecked Sendable {
        private let lock = NSLock()
        private var result: Result<Value, Error>?
        private var continuation: CheckedContinuation<Value, Error>?
        private var worker: Task<Void, Never>?
        private var timer: DispatchSourceTimer?

        func install(_ continuation: CheckedContinuation<Value, Error>) {
            lock.lock()
            if let result {
                lock.unlock()
                continuation.resume(with: result)
            } else {
                self.continuation = continuation
                lock.unlock()
            }
        }

        func install(worker: Task<Void, Never>, timer: DispatchSourceTimer) {
            lock.lock()
            if result != nil {
                lock.unlock()
                worker.cancel()
                timer.cancel()
            } else {
                self.worker = worker
                self.timer = timer
                lock.unlock()
            }
        }

        func finish(_ result: Result<Value, Error>) {
            lock.lock()
            guard self.result == nil else { lock.unlock(); return }
            self.result = result
            let continuation = self.continuation
            self.continuation = nil
            let worker = self.worker
            let timer = self.timer
            self.worker = nil
            self.timer = nil
            lock.unlock()
            continuation?.resume(with: result)
            worker?.cancel()
            timer?.cancel()
        }
    }
}
