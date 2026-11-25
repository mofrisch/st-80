import Foundation
import SmalltalkCore
import SwiftUI

extension AppController {
    private func activeButton(for command: String) -> (windowID: Int64, button: UIElementInfo)? {
        guard keyInspectorID == nil, let window = windowPresentation.activeWindow?.info,
              let root = window.content else { return nil }
        let enabled = root.firstVisible(where: { $0.command == command && canPerform($0, in: window.id) })
        guard let button = enabled ?? root.firstVisible(where: {
            $0.command == command && canQueueAfterEditorFlush($0, in: window.id)
        }) else { return nil }
        return (window.id, button)
    }

    private func canQueueAfterEditorFlush(_ button: UIElementInfo, in windowID: Int64) -> Bool {
        // A native draft can change Accept's availability at the next VM update.
        button.command == "acceptMethod" && !windowPresentation.isRecovering && hasPendingEditorInput(in: windowID)
    }

    func hasCommand(_ command: String) -> Bool { activeButton(for: command) != nil }

    func performCommand(_ command: String) async {
        guard let target = activeButton(for: command) else { return }
        await clickControl(windowID: target.windowID, elementID: target.button.id)
    }

    func canPerform(_ element: UIElementInfo, in windowID: Int64) -> Bool {
        guard element.enabled else { return false }
        if windowPresentation.isRecovering {
            switch element.kind {
            case .button:
                return presentedWindow(windowID)?.info.kind == .workspace &&
                    element.command.flatMap(WorkspaceRecoveryAction.init(command:)) != nil
            case .codeEditor:
                guard let window = presentedWindow(windowID)?.info else { return false }
                return workspaceEditor(in: window)?.id == element.id
            case .textField, .list, .historyList, .valueTable: return false
            default: return true
            }
        }
        return true
    }

    func workspaceEditor(in window: ToolWindowInfo) -> UIElementInfo? {
        guard window.kind == .workspace else { return nil }
        return window.content?.firstVisible {
            $0.kind == .codeEditor && $0.accessibilityID == "workspaceEditor" && $0.enabled
        }
    }

    var applicationCommandWindow: ToolWindowInfo? {
        guard !windowPresentation.isRecovering, keyInspectorID == nil else { return nil }
        return windowPresentation.activeWindow?.info
    }

    func performApplicationCommand(_ id: String, in window: ToolWindowInfo) async {
        guard !isRunning, let current = applicationCommandWindow,
              current.id == window.id, current.identity == window.identity,
              current.content?.applicationCommands.contains(where: { $0.id == id && $0.kind == .button && $0.enabled }) == true else { return }
        await clickControl(windowID: window.id, elementID: id)
    }

    private var recoveryCommandTarget: (window: ToolWindowInfo, editor: UIElementInfo)? {
        guard windowPresentation.isRecovering, keyInspectorID == nil,
              let window = windowPresentation.activeWindow?.info, let editor = workspaceEditor(in: window) else { return nil }
        return (window, editor)
    }

    var canRunRecoveryCommands: Bool { !isRunning && recoveryCommandTarget != nil }

    func performRecoveryCommand(_ action: WorkspaceRecoveryAction) async {
        guard !isRunning, let (window, editor) = recoveryCommandTarget else { return }
        let text = inputText(windowID: window.id, element: editor)
        let selection = selectedText(in: editor, windowID: window.id, text: text)
        await recoverWorkspace(window, editor: editor, action: action, selection: selection)
    }

    func editorContextItems(windowID: Int64, editor: UIElementInfo) -> [EditorContextItem] {
        guard windowPresentation.isRecovering else {
            return (editor.contextMenuItems ?? []).compactMap(EditorContextItem.init(projected:))
        }
        guard let window = presentedWindow(windowID)?.info, workspaceEditor(in: window)?.id == editor.id else { return [] }
        return [
            .command(title: "Do it", identifier: "doIt", action: .recovery(.evaluate, editorID: editor.id), enabled: true),
            .command(title: "Print it", identifier: "printIt", action: .recovery(.print, editorID: editor.id), enabled: true),
            .command(title: "Inspect it", identifier: "inspectIt", action: .recovery(.inspect, editorID: editor.id), enabled: true)
        ]
    }

    func performEditorContextAction(_ action: EditorContextAction, windowID: Int64, selection: String) async {
        switch action {
        case .control(let id):
            guard !windowPresentation.isRecovering else { return }
            await clickControl(windowID: windowID, elementID: id, selection: selection)
        case .recovery(let command, let editorID):
            guard windowPresentation.isRecovering, let window = presentedWindow(windowID)?.info,
                  let editor = workspaceEditor(in: window), editor.id == editorID else { return }
            await recoverWorkspace(window, editor: editor, action: command, selection: selection)
        }
    }

    func stopDebugging() {
        debuggerStopRequested = true
        debugSession?.send(.stop)
    }

    func debugWorkspace(windowID: Int64, editorID: String, source: String) async {
        guard let window = presentedWindow(windowID)?.info, workspaceEditor(in: window)?.id == editorID else { return }
        await runOperation {
            let debuggerWindowID = UUID()
            var presentation: DebuggerPresentationState?
            debuggerStopRequested = false
            defer {
                presentation?.cancel()
                nativeWindows?.closeTransientWindow(debuggerWindowID)
                debugSession = nil
            }
            await attemptToFlushWindowState()
            guard !debuggerStopRequested,
                  let current = presentedWindow(windowID)?.info, workspaceEditor(in: current)?.id == editorID else { return }
            let debugging = await session.debugSource(source, workspaceID: windowID)
            debugSession = debugging
            if debuggerStopRequested { debugging.send(.stop) }
            for await event in debugging.events {
                switch event {
                case .paused(let snapshot):
                    guard !debuggerStopRequested else { continue }
                    if let presentation {
                        presentation.update(snapshot)
                        nativeWindows?.activateTransientWindow(debuggerWindowID)
                        continue
                    }
                    guard let nativeWindows, let info = try? await snapshot.windowInfo() else {
                        stopDebugging()
                        continue
                    }
                    guard !debuggerStopRequested else { continue }
                    let state = DebuggerPresentationState(snapshot: snapshot) { [weak self] command in
                        if case .stop = command { self?.stopDebugging() }
                        else { self?.debugSession?.send(command) }
                    }
                    presentation = state
                    let content = SnapshotWindowContentView(content: { state.content }, click: state.click, select: state.select)
                    nativeWindows.showTransientWindow(debuggerWindowID, info: info, content: AnyView(content), onClose: state.stop)
                case .finished(let evaluation):
                    applyControlResult(evaluation, windowID: windowID)
                    return
                }
            }
        }
    }

    func openInspector(_ snapshot: InspectorSnapshot) {
        let id = snapshot.id
        if inspectors[id] != nil {
            nativeWindows?.activateTransientWindow(id)
            return
        }

        let state = InspectorPresentationState(snapshot: snapshot, session: session)
        inspectors[id] = state
        Task { [weak self, session] in
            do {
                let info = try await session.inspectorWindowInfo(for: id)
                guard let self, inspectors[id] === state else { return }
                guard let nativeWindows else { closeInspector(id); return }
                let content = SnapshotWindowContentView(content: { state.content }, isLoading: { state.isLoading },
                                                        click: state.click, select: state.select)
                nativeWindows.showTransientWindow(id, info: info, content: AnyView(content), onKeyChange: { [weak self] isKey in
                    guard let self else { return }
                    if isKey { keyInspectorID = id }
                    else if keyInspectorID == id { keyInspectorID = nil }
                }, onClose: { [weak self] in self?.closeInspector(id) })
            } catch {
                guard let self, inspectors[id] === state else { return }
                self.error = error.localizedDescription
                closeInspector(id)
            }
        }
    }

    func closeInspectors() {
        for id in Array(inspectors.keys) { closeInspector(id) }
    }

    private func closeInspector(_ id: UUID) {
        guard let state = inspectors.removeValue(forKey: id) else { return }
        if keyInspectorID == id { keyInspectorID = nil }
        nativeWindows?.closeTransientWindow(id)
        state.close()
    }

    func clickControl(windowID: Int64, elementID: String, selection capturedSelection: String? = nil) async {
        guard let window = presentedWindow(windowID)?.info,
              let root = window.content, let button = root.firstVisible(where: { $0.id == elementID }),
              canPerform(button, in: windowID) || canQueueAfterEditorFlush(button, in: windowID) else { return }
        let selection = capturedSelection ?? selectedText(for: button, in: windowID, root: root)
        if windowPresentation.isRecovering, window.kind == .workspace,
           let command = button.command, let action = WorkspaceRecoveryAction(command: command),
           let editor = workspaceEditor(in: window) {
            await recoverWorkspace(window, editor: editor, action: action, selection: selection)
            return
        }
        let flushPolicy: ControlFlushPolicy
        if button.command == "acceptMethod" {
            flushPolicy = .requireEditorFlush(windowIdentity: window.identity)
        } else {
            flushPolicy = window.kind == .workspace || window.kind == .browser ? .bestEffort : .requireSuccess
        }
        await sendControl(.click(windowID: windowID, elementID: elementID, selection: selection),
                          windowID: windowID, flushPolicy: flushPolicy)
    }

    private func selectedText(for button: UIElementInfo, in windowID: Int64, root: UIElementInfo) -> String {
        guard let source = button.selectionSource, let editor = root.firstVisible(where: { $0.id == source }) else { return "" }
        return selectedText(in: editor, windowID: windowID, text: inputText(windowID: windowID, element: editor))
    }

    private func selectedText(in editor: UIElementInfo, windowID: Int64, text: String) -> String {
        let text = text as NSString
        let range = editorSelection(windowID: windowID, elementID: editor.id)
        guard range.location >= 0, range.location <= text.length,
              range.length >= 0, range.length <= text.length - range.location else { return "" }
        return text.substring(with: range)
    }

    func selectControl(windowID: Int64, elementID: String, value: String?) async {
        await sendControl(.select(windowID: windowID, elementID: elementID, value: value), windowID: windowID, flushPolicy: .bestEffort)
    }

    private enum ControlFlushPolicy {
        case requireSuccess, bestEffort
        case requireEditorFlush(windowIdentity: String)
    }

    private func sendControl(_ action: UIAction, windowID: Int64, flushPolicy: ControlFlushPolicy) async {
        await runOperation {
            switch flushPolicy {
            case .requireSuccess:
                guard await flushWindowStateRequiringSuccess() else { return }
            case .requireEditorFlush(let identity):
                await attemptToFlushWindowState()
                guard !windowPresentation.isRecovering, !hasPendingEditorInput(in: windowID),
                      presentedWindow(windowID)?.info.identity == identity else { return }
            case .bestEffort:
                await attemptToFlushWindowState()
            }
            let evaluation = await session.uiAction(action)
            applyControlResult(evaluation, windowID: windowID)
        }
    }
}
