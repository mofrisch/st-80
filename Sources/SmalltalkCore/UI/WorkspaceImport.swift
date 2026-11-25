import Foundation

package struct WorkspaceImportResult: Sendable {
    package let evaluation: EvaluationResult
    package let outcome: Result<ToolWindowInfo, SmalltalkError>
}

extension SmalltalkSession {
    package func openWorkspace(source: String) async -> WorkspaceImportResult {
        await worker.submit { $0.openWorkspace(source: source) }
    }
}

extension SmalltalkRuntime {
    func openWorkspace(source: String) -> WorkspaceImportResult {
        beginEvaluation()
        let target: (id: Int64, identity: String)
        do {
            target = try createWorkspace(containing: source)
        } catch {
            let reason = error.localizedDescription
            return WorkspaceImportResult(evaluation: finishEvaluation(error: reason), outcome: .failure(SmalltalkError(reason)))
        }

        let evaluation = finishEvaluation()
        let outcome: Result<ToolWindowInfo, SmalltalkError>
        if let error = evaluation.executionError {
            outcome = .failure(SmalltalkError(error))
        } else if let workspace = evaluation.windows.first(where: {
            $0.id == target.id && $0.identity == target.identity && $0.kind == .workspace
        }) {
            outcome = .success(workspace)
        } else {
            outcome = .failure(SmalltalkError(evaluation.windowProjectionError ?? "The newly opened workspace is no longer available."))
        }
        return WorkspaceImportResult(evaluation: evaluation, outcome: outcome)
    }

    private func createWorkspace(containing source: String) throws -> (id: Int64, identity: String) {
        guard let desktop = globals["Desktop"] else { throw SmalltalkError("Desktop is missing.") }
        let existing = Set((desktopWindows?.elements ?? []).compactMap { value -> String? in
            guard case .object(let window) = value else { return nil }
            return window.nativeID
        })

        let opened = try send(desktop, "openWorkspace", [])
        if case .nilValue = opened, (desktopWindows?.elements.count ?? 0) >= Self.desktopWindowLimit {
            throw SmalltalkError("Could not open the workspace: the desktop is limited to \(Self.desktopWindowLimit) windows. Close a window and try again.")
        }
        // The window returned by Smalltalk need not be the active window.
        // Never write into an existing window returned by a custom open policy.
        guard case .object(let window) = opened, !existing.contains(window.nativeID),
              case .symbol("workspace")? = window.fields["kind"],
              case .integer(let id)? = window.fields["id"], id > 0,
              projectedWindow(withID: id) === window else {
            throw SmalltalkError("Could not open the workspace: Smalltalk did not create a new workspace window.")
        }
        _ = try send(opened, "text:", [.string(source)])
        return (id, window.nativeID)
    }
}
