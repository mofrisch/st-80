import Foundation

/// An isolated, persistent object space. Evaluations run away from the UI actor.
public actor SmalltalkSession {
    let worker: InterpreterWorker

    public init() {
        worker = InterpreterWorker()
    }

    package init(confirmWarning: @escaping @Sendable (WarningPrompt) -> Bool) {
        worker = InterpreterWorker(confirmWarning: confirmWarning)
    }

    public func evaluate(_ source: String) async -> EvaluationResult {
        await worker.submit { $0.run(source) }
    }

    /// Reads an ANSI Smalltalk Interchange Format 1.0 file into this session.
    public func importInterchange(from url: URL) async throws -> EvaluationResult {
        try await importInterchange(from: [url])
    }

    /// Loads the files of one program and runs their initializers in the order given.
    public func importInterchange(from urls: [URL]) async throws -> EvaluationResult {
        guard !urls.isEmpty else { throw SmalltalkInterchange.invalid("Select at least one interchange file.") }
        var remainingBytes = SmalltalkInterchange.maximumBytes
        let sources = try urls.map { url in
            let data = try SourceJournal.readBounded(url, maximum: remainingBytes)
            remainingBytes -= data.count
            guard let source = String(data: data, encoding: .utf8) else {
                throw SmalltalkInterchange.invalid("\(url.lastPathComponent) must be UTF-8.")
            }
            return source
        }
        return await worker.submit { $0.runInterchange(sources) }
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
