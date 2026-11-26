import Foundation

public enum UIAction: Sendable {
    case click(windowID: Int64, elementID: String, selection: String = "")
    case select(windowID: Int64, elementID: String, value: String?)
    case text(windowID: Int64, elementID: String, value: String)
}

package enum UIActionDisposition: Equatable, Sendable {
    case applied
    case ignored
    case rejected(String)
}

package struct UIActionResult: Sendable {
    package let evaluation: EvaluationResult
    package let disposition: UIActionDisposition
}

extension SmalltalkSession {
    public func uiAction(_ action: UIAction) async -> EvaluationResult {
        await dispatchUIAction(action).evaluation
    }

    package func uiAction(_ action: UIAction, execution: WorkspaceExecution) async -> EvaluationResult {
        await withTaskCancellationHandler {
            await worker.submit { $0.performUIAction(action, execution: execution).evaluation }
        } onCancel: {
            execution.stop()
        }
    }

    package func dispatchUIAction(_ action: UIAction) async -> UIActionResult {
        await worker.submit { $0.performUIAction(action) }
    }
}

extension SmalltalkRuntime {
    func performUIAction(_ action: UIAction, execution: WorkspaceExecution? = nil) -> UIActionResult {
        beginEvaluation()
        let evaluation: EvaluationResult
        do {
            let windowID: Int64, elementID: String
            switch action {
            case .click(let window, let element, _), .text(let window, let element, _), .select(let window, let element, _):
                windowID = window; elementID = element
            }
            guard let control = try projectedActionTarget(windowID: windowID, elementID: elementID) else {
                return UIActionResult(evaluation: snapshot(), disposition: .ignored)
            }
            let result: Value
            switch action {
            case .click(_, _, let selection):
                guard control.kind == .button else { throw SmalltalkError("The element is not a button.") }
                guard selection.utf8.count <= 65_536 else { throw SmalltalkError("The selection is too large.") }
                result = try withWorkspaceExecution(execution) {
                    try send(.object(control.object), "clickWithSelection:", [.string(selection)])
                }
            case .select(_, _, let value):
                guard control.kind == .list || control.kind == .historyList || control.kind == .valueTable else { throw SmalltalkError("The element does not support selection.") }
                if control.kind == .valueTable, case .boolean(true)? = control.object.fields["readOnly"] {
                    return UIActionResult(evaluation: snapshot(), disposition: .ignored)
                }
                result = try send(.object(control.object), "select:", [value.map(Value.string) ?? .nilValue])
            case .text(_, _, let text):
                guard control.kind == .textField || control.kind == .codeEditor,
                      text.utf8.count <= 65_536 else { throw SmalltalkError("Invalid text input. The limit is 64 KiB.") }
                if case .boolean(true)? = control.object.fields["readOnly"] {
                    return UIActionResult(evaluation: snapshot(), disposition: .ignored)
                }
                result = try send(.object(control.object), "editText:", [.string(text)])
            }
            evaluation = finishEvaluation(value: printValue(result))
        } catch {
            evaluation = finishEvaluation(error: error.localizedDescription)
        }
        let disposition = evaluation.executionError.map(UIActionDisposition.rejected) ?? .applied
        return UIActionResult(evaluation: evaluation, disposition: disposition)
    }
}
