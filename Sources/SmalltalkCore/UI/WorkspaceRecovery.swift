package enum WorkspaceRecoveryAction: String, Sendable {
    case evaluate = "doIt", print = "printIt", inspect = "inspectIt"

    package init?(command: String) {
        self.init(rawValue: command)
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
            guard let services = classes["ToolServices"] else { throw SmalltalkError("Tool services are missing.") }
            let policy = try SystemLibrary.shared.get().bundledClass("WorkspaceRecoveryCommands", in: self)
            let outcome = try send(.classObject(policy), "\(action.rawValue):services:transcript:", [
                .string(source), .object(try object(services)), globals["Transcript"] ?? .nilValue,
            ])
            guard case .array(let result) = outcome, result.elements.count == 2,
                  case .boolean(let success) = result.elements[0], case .string(let message) = result.elements[1] else {
                throw SmalltalkError("Workspace recovery returned an invalid result.")
            }
            if success { value = message } else { failure = message }
        } catch {
            failure = error.localizedDescription
        }

        // Drain tool requests only here; an inspector opened above must reach
        // the app even when Desktop still cannot produce a valid projection.
        return finishWorkspaceEvaluation(value: value, error: failure, target: (windowID, identity))
    }
}
