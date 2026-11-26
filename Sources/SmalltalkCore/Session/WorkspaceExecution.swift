import Foundation
import os

protocol ExecutionCancellation: Sendable {
    func checkStop() throws
}

private struct WorkspaceExecutionStopped: LocalizedError {
    var errorDescription: String? { "Execution stopped." }
}

/// A single Workspace run. Stop can signal it without waiting for the VM queue.
package final class WorkspaceExecution: ExecutionCancellation {
    let stepLimit: Int
    private let stopped = OSAllocatedUnfairLock(initialState: false)

    package init(stepLimit: Int? = nil) {
        self.stepLimit = max(SmalltalkRuntime.executionStepLimit, stepLimit ?? 0)
    }

    package func stop() {
        stopped.withLock { $0 = true }
    }

    func checkStop() throws {
        if stopped.withLock({ $0 }) { throw WorkspaceExecutionStopped() }
    }
}
