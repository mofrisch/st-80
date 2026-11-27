import Foundation

/// Swift's cooperative executor has small stacks. A bounded recursive interpreter
/// uses a dedicated thread; mutable language objects never leave that thread.
final class InterpreterWorker: Sendable {
    private struct Job: Sendable {
        let operation: @Sendable (inout SmalltalkRuntime) -> Void
        let cancellation: (@Sendable () -> Void)?

        init(operation: @escaping @Sendable (inout SmalltalkRuntime) -> Void, cancellation: (@Sendable () -> Void)? = nil) {
            self.operation = operation
            self.cancellation = cancellation
        }
    }

    // All mutable state is protected by condition, including shutdown.
    private final class Queue: @unchecked Sendable {
        let condition = NSCondition()
        var jobs: [Job] = []
        var stopping = false
        var activeCancellation: (@Sendable () -> Void)?
    }

    /// Leave room for the compiler's depth guard even with unoptimized VM frames.
    /// VMRegressionTests runs those cases on a thread of this size.
    static let stackSize = 32 * 1_024 * 1_024

    private let queue: Queue

    init(bootstrap: Bool = true, confirmWarning: (@Sendable (WarningPrompt) -> Bool)? = nil) {
        let queue = Queue()
        self.queue = queue
        // Foundation retains a started Thread until its entry closure finishes.
        let thread = Thread {
            var runtime = SmalltalkRuntime(bootstrap: bootstrap)
            while true {
                queue.condition.lock()
                queue.activeCancellation = nil
                while queue.jobs.isEmpty && !queue.stopping { queue.condition.wait() }
                if queue.jobs.isEmpty && queue.stopping { queue.condition.unlock(); return }
                let job = queue.jobs.removeFirst()
                queue.activeCancellation = job.cancellation
                queue.condition.unlock()
                autoreleasepool {
                    runtime.confirmWarning = confirmWarning
                    job.operation(&runtime)
                    runtime.collectGarbageIfDue()
                }
            }
        }
        thread.name = bootstrap ? "Smalltalk interpreter" : "Smalltalk source scanner"
        thread.stackSize = Self.stackSize
        thread.start()
    }

    deinit {
        queue.condition.lock()
        queue.stopping = true
        var cancellations = queue.jobs.compactMap(\.cancellation)
        if let active = queue.activeCancellation { cancellations.append(active) }
        queue.condition.signal()
        queue.condition.unlock()
        cancellations.forEach { $0() }
    }

    func submit<T: Sendable>(_ operation: @escaping @Sendable (inout SmalltalkRuntime) -> T) async -> T {
        await withCheckedContinuation { continuation in
            enqueue(Job(operation: { runtime in continuation.resume(returning: operation(&runtime)) }))
        }
    }

    func submitThrowing<T: Sendable>(_ operation: @escaping @Sendable (inout SmalltalkRuntime) throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            enqueue(Job(operation: { runtime in
                do { continuation.resume(returning: try operation(&runtime)) }
                catch { continuation.resume(throwing: error) }
            }))
        }
    }

    func submit(onCancellation: @escaping @Sendable () -> Void, _ operation: @escaping @Sendable (inout SmalltalkRuntime) -> Void) {
        enqueue(Job(operation: operation, cancellation: onCancellation))
    }

    private func enqueue(_ job: Job) {
        queue.condition.lock()
        queue.jobs.append(job)
        queue.condition.signal()
        queue.condition.unlock()
    }
}
