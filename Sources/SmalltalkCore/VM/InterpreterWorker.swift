import Foundation

/// Swift's cooperative executor has small stacks. A bounded recursive interpreter
/// uses a dedicated thread; mutable language objects never leave that thread.
final class InterpreterWorker: Sendable {
    private struct Job: Sendable {
        let operation: @Sendable (inout SmalltalkRuntime) -> Void
    }

    // All mutable state is protected by condition, including shutdown.
    private final class Queue: @unchecked Sendable {
        let condition = NSCondition()
        var jobs: [Job] = []
        var stopping = false
    }

    private let queue: Queue

    init() {
        let queue = Queue()
        self.queue = queue
        // Foundation retains a started Thread until its entry closure finishes.
        let thread = Thread {
            var runtime = SmalltalkRuntime()
            while true {
                queue.condition.lock()
                while queue.jobs.isEmpty && !queue.stopping { queue.condition.wait() }
                if queue.jobs.isEmpty && queue.stopping { queue.condition.unlock(); return }
                let job = queue.jobs.removeFirst()
                queue.condition.unlock()
                autoreleasepool { job.operation(&runtime) }
            }
        }
        thread.name = "Smalltalk interpreter"
        thread.stackSize = 16 * 1_024 * 1_024
        thread.start()
    }

    deinit {
        queue.condition.lock()
        queue.stopping = true
        queue.condition.signal()
        queue.condition.unlock()
    }

    func submit<T: Sendable>(_ operation: @escaping @Sendable (inout SmalltalkRuntime) -> T) async -> T {
        await withCheckedContinuation { continuation in
            enqueue(Job { runtime in continuation.resume(returning: operation(&runtime)) })
        }
    }

    func submitThrowing<T: Sendable>(_ operation: @escaping @Sendable (inout SmalltalkRuntime) throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            enqueue(Job { runtime in
                do { continuation.resume(returning: try operation(&runtime)) }
                catch { continuation.resume(throwing: error) }
            })
        }
    }

    private func enqueue(_ job: Job) {
        queue.condition.lock()
        queue.jobs.append(job)
        queue.condition.signal()
        queue.condition.unlock()
    }
}
