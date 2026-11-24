import Foundation

extension SmalltalkSession {
    /// A failed journal initialization must leave the current world available.
    public func reset(startingChangeLogAt url: URL) async throws -> EvaluationResult {
        try await worker.submitThrowing { runtime in
            let replacement = SmalltalkRuntime()
            if let error = replacement.bootstrapError { throw SmalltalkError(error) }
            try replacement.journal.attach(to: url)
            let evaluation = replacement.snapshot()
            runtime = replacement
            return evaluation
        }
    }
}
