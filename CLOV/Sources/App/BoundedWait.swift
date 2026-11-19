import Foundation

/// Runs `operation` but stops waiting for it after `timeout`.
///
/// Unlike a task group, this returns on time even when the operation never
/// checks for cancellation: the timeout cancels it and the caller moves on.
/// Use it only for best-effort work whose result the caller does not need.
func runBounded(
    timeout: Duration,
    operation: @escaping @Sendable () async -> Void
) async {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        let gate = ResumeOnce(continuation)
        let work = Task {
            await operation()
            gate.resume()
        }
        Task {
            try? await Task.sleep(for: timeout)
            work.cancel()
            gate.resume()
        }
    }
}

private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?

    init(_ continuation: CheckedContinuation<Void, Never>) {
        self.continuation = continuation
    }

    func resume() {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume()
    }
}
