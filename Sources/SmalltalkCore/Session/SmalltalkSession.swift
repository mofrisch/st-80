import Foundation

/// An isolated, persistent object space. Evaluations run away from the UI actor.
public actor SmalltalkSession {
    let worker = InterpreterWorker()

    public init() {}

    public func evaluate(_ source: String) async -> EvaluationResult {
        await worker.submit { $0.run(source) }
    }

    public func inspectSource(_ source: String) async -> EvaluationResult {
        await worker.submit { $0.run(source, inspectingResult: true) }
    }

    public func snapshot() async -> EvaluationResult { await worker.submit { $0.snapshot() } }

    public func compile(_ source: String, in className: String, side: MethodSide = .instance) async -> EvaluationResult {
        await worker.submit { runtime in
            runtime.beginEvaluation()
            do {
                guard let stClass = runtime.classes[className] else { throw SmalltalkError("Class \(className) does not exist.") }
                let selector = try runtime.compile(source, in: stClass, side: side)
                return runtime.finishEvaluation(value: "\(side.displayName(for: className)) » \(selector)")
            } catch { return runtime.snapshot(error: error.localizedDescription) }
        }
    }

    public func reset() async -> EvaluationResult {
        await worker.submit { runtime in
            runtime = SmalltalkRuntime()
            return runtime.snapshot()
        }
    }
}
