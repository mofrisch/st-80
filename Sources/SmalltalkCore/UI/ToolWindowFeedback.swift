package struct ToolWindowFeedback: Equatable, Sendable {
    let recoveryResult: String?
    let inputError: String?
    let activeError: String?
    let displayedResult: String?

    package init?(recoveryResult: String?, inputError: String?, activeError: String?, displayedResult: String?) {
        guard recoveryResult != nil || inputError != nil || activeError != nil else { return nil }
        self.recoveryResult = recoveryResult
        self.inputError = inputError
        self.activeError = activeError
        self.displayedResult = displayedResult
    }
}

extension SmalltalkSession {
    // The live VM and its desktop may be busy or damaged when this view is needed.
    private static let bundledFeedbackWorker = InterpreterWorker()

    package static func toolWindowFeedback(_ feedback: ToolWindowFeedback) async -> UIElementInfo? {
        try? await bundledFeedbackWorker.submitThrowing { runtime in
            if let error = runtime.bootstrapError { throw SmalltalkError(error) }
            guard let presenter = runtime.globals["ToolWindowFeedback"] else {
                throw SmalltalkError("The tool window feedback class is missing.")
            }
            runtime.steps = 0
            let tree = try runtime.send(presenter, "contentFor:inputError:activeError:displayedResult:", [
                feedback.recoveryResult.map(Value.string) ?? .nilValue,
                feedback.inputError.map(Value.string) ?? .nilValue,
                feedback.activeError.map(Value.string) ?? .nilValue,
                feedback.displayedResult.map(Value.string) ?? .nilValue,
            ])
            return try runtime.projectContent(tree)
        }
    }
}
