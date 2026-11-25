import Foundation

package enum WorkspaceRecoveryAction: Equatable, Sendable {
    case evaluate, print, inspect

    package init?(command: String) {
        switch command {
        case "doIt": self = .evaluate
        case "printIt": self = .print
        case "inspectIt": self = .inspect
        default: return nil
        }
    }
}

extension SmalltalkSession {
    /// A retained native workspace can repair a broken Desktop without sending
    /// messages through that Desktop's controls or retaining its old VM objects.
    package func recoverWorkspace(source: String, action: WorkspaceRecoveryAction,
                                  windowID: Int64, identity: String, epoch: String) async -> EvaluationResult {
        await worker.submit { runtime in
            runtime.recoverWorkspace(source: source, action: action, windowID: windowID, identity: identity, epoch: epoch)
        }
    }
}

extension SmalltalkRuntime {
    fileprivate func recoverWorkspace(source: String, action: WorkspaceRecoveryAction,
                                      windowID: Int64, identity: String, epoch: String) -> EvaluationResult {
        guard epoch == windowEpoch else { return snapshot() }
        let current = projectWindows()
        if let replacement = current.windows.first(where: { $0.id == windowID }), replacement.identity != identity {
            return snapshot()
        }
        if current.error == nil {
            guard let workspace = projectedWindow(withID: windowID), workspace.nativeID == identity,
                  isUIClass(workspace.stClass, named: "WorkspaceWindow") else { return snapshot() }
        }

        beginEvaluation()
        catalogDirty = true
        var value: String?
        var failure: String?
        do {
            guard source.utf8.count <= 65_536 else {
                throw SmalltalkError("Workspace recovery source is limited to 64 KiB.")
            }
            if action == .inspect, source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw SmalltalkError("Enter an expression to inspect.")
            }
            guard !evaluatingToolSource else { throw SmalltalkError("A workspace evaluation is already running.") }
            evaluatingToolSource = true
            defer { evaluatingToolSource = false }
            let evaluated = try evaluate(source)
            switch action {
            case .evaluate:
                value = printValue(evaluated)
            case .print:
                let printed = printValue(evaluated)
                guard let output = globals["Transcript"] else { throw SmalltalkError("Transcript is missing.") }
                _ = try send(output, "show:", [.string("→ " + printed)])
                _ = try send(output, "cr", [])
                value = printed
            case .inspect:
                try requestInspection(evaluated)
                value = "Object Inspector opened."
            }
        } catch {
            failure = error.localizedDescription
        }

        // Drain tool requests only here; an inspector opened above must reach
        // the app even when Desktop still cannot produce a valid projection.
        return finishWorkspaceEvaluation(value: value, error: failure, target: (windowID, identity))
    }
}
