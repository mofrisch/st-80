import AppKit
import SmalltalkCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class AppController {
    private var windowPresentation = WindowPresentation()
    private var controlEdits = ControlEdits()
    private var operationError: String?
    private var projectionError: String?
    private var persistenceError: String?
    var error: String? {
        get {
            var seen: Set<String> = []
            let messages = [projectionError, operationError, persistenceError].compactMap { $0 }
                .filter { seen.insert($0).inserted }
            return messages.isEmpty ? nil : messages.joined(separator: "\n")
        }
        set { operationError = newValue }
    }
    var isRunning = false {
        didSet {
            if !isRunning {
                let waiter = operationWaiter
                operationWaiter = nil
                waiter?.resume()
                scheduleWindowSynchronization()
                scheduleInputSynchronization()
            }
        }
    }
    @ObservationIgnored private var operationWaiter: CheckedContinuation<Void, Never>?
    var imageURL: URL?
    private(set) var imageHasChanges = false
    private let session = SmalltalkSession()
    @ObservationIgnored private var inspectors: [UUID: InspectorPresentationState] = [:]
    private var keyInspectorID: UUID?
    @ObservationIgnored private var debugSession: WorkspaceDebugSession?
    @ObservationIgnored private var debuggerStopRequested = false
    private var hasLoaded = false
    @ObservationIgnored private var inputDebounce: Task<Void, Never>?
    @ObservationIgnored private var inputFlush: (id: UUID, task: Task<Bool, Never>)?
    @ObservationIgnored private var inputEpoch = 0
    private var pendingWindowEvents: [NativeWindowEvent] = []
    @ObservationIgnored private var windowFlush: (id: UUID, task: Task<Bool, Never>)?
    @ObservationIgnored private var windowEpoch = 0
    private var windowDebounce: Task<Void, Never>?
    private var currentEpoch: String?
    private var latestRevision: Int64 = 0
    private var changesPath: String?
    @ObservationIgnored private var nativeWindows: NativeWindowBackend?
    private static var imageType: UTType { UTType(filenameExtension: "stimage", conformingTo: .data) ?? .data }

    var activeKind: ToolKind? { windowPresentation.activeWindow?.info.kind }
    var activeWindowID: Int64? { windowPresentation.activeID }
    var workspaceWindow: ToolWindowInfo? { windowPresentation.workspace?.info }
    var workspaceAppMenus: [UIElementInfo] {
        workspaceWindow?.content?.children.filter { $0.role == "applicationMenu" && $0.visible } ?? []
    }

    func presentedWindow(_ id: Int64) -> PresentedWindow? { windowPresentation.window(id) }

    func load() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        nativeWindows = NativeWindowBackend(
            content: { [weak self] id in
                guard let self else { return AnyView(EmptyView()) }
                return AnyView(ToolContentView(controller: self, windowID: id))
            },
            toolbar: { [weak self] info in
                guard let self, info.content?.windowToolbar != nil else { return nil }
                return AnyView(WindowToolbarView(controller: self, windowID: info.id))
            },
            onEvent: { [weak self] event in self?.received(event) }
        )
        isRunning = true
        defer { isRunning = false }
        do { try await startUnsavedChangeLog() }
        catch { persistenceError = "Changes cannot be recorded on disk: \(error.localizedDescription)" }
        apply(await session.snapshot(), replacingWindows: true)
        await arrangeInitialTools()
    }

    private func arrangeInitialTools() async {
        // Presenting the first snapshot supplies the native display facts.
        guard await synchronizeWindowEvents() else { return }
        apply(await session.windowAction(.arrangeTools))
    }

    private func received(_ event: NativeWindowEvent) {
        pendingWindowEvents.append(event)
        switch event.kind {
        case .activated(let id):
            if presentedWindow(id) != nil, windowPresentation.activeID != id {
                windowPresentation.activeID = id
                imageHasChanges = true
            }
        case .closeRequested, .frame, .minimized:
            imageHasChanges = true
        case .screens, .frameApplied:
            // AppKit also sends these when presenting a fresh or restored desktop.
            break
        }
        scheduleWindowSynchronization()
    }

    func imageNeedsSaving() -> Bool {
        nativeWindows?.captureGeometry()
        return imageHasChanges
    }

    /// The application delegate waits here for a command already in progress.
    func waitForCurrentOperation() async {
        while isRunning {
            await withCheckedContinuation { operationWaiter = $0 }
        }
    }

    private func scheduleWindowSynchronization() {
        guard hasLoaded, !isRunning, windowDebounce == nil, !pendingWindowEvents.isEmpty else { return }
        windowDebounce = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(40)) } catch { return }
            guard let self else { return }
            self.windowDebounce = nil
            guard !self.isRunning else { return }
            _ = await self.synchronizeWindowEvents()
        }
    }

    private func synchronizeWindowEvents() async -> Bool {
        while true {
            if let running = windowFlush {
                let success = await running.task.value
                if windowFlush?.id == running.id { windowFlush = nil }
                if !success { return false }
            } else if pendingWindowEvents.isEmpty { return true }
            else {
                let id = UUID(), epoch = windowEpoch
                let events = pendingWindowEvents; pendingWindowEvents.removeAll()
                let task = Task { [weak self] in
                    guard let self else { return true }
                    let evaluation = await self.session.windowEvents(events)
                    guard epoch == self.windowEpoch else { return true }
                    self.apply(evaluation)
                    return evaluation.executionError == nil
                }
                windowFlush = (id, task)
            }
        }
    }

    private func apply(_ evaluation: EvaluationResult, replacingWindows: Bool = false) {
        if !replacingWindows, let currentEpoch {
            guard evaluation.windowCommands.epoch == currentEpoch else { return }
            if evaluation.windowCommands.revision < latestRevision {
                // A newer window snapshot may arrive first. An inspector
                // request still owns a live root in this session.
                for case .openInspector(let snapshot) in evaluation.toolRequests {
                    openInspector(snapshot)
                }
                return
            }
            guard evaluation.windowCommands.revision > latestRevision else { return }
        }
        currentEpoch = evaluation.windowCommands.epoch
        latestRevision = evaluation.windowCommands.revision
        if replacingWindows {
            for id in Array(inspectors.keys) { closeInspector(id) }
        }
        changesPath = evaluation.changesPath
        projectionError = evaluation.windowProjectionError
        error = evaluation.executionError ?? (projectionError == nil ? evaluation.error : nil)
        windowPresentation.update(from: evaluation, replacingWindows: replacingWindows)
        controlEdits.reconcile(with: windowPresentation.windows.map(\.info))
        nativeWindows?.execute(evaluation.windowCommands, preservingWindows: windowPresentation.isRecovering,
                               recoveryWorkspace: windowPresentation.isRecovering ? windowPresentation.workspace?.info : nil)
        for request in evaluation.toolRequests {
            switch request {
            case .saveImage:
                Task { [weak self] in await self?.saveImage() }
            case .showVersions(let className, let selector, let side):
                Task { [weak self] in await self?.showChanges(className: className, selector: selector, side: side) }
            case .openInspector(let snapshot):
                openInspector(snapshot)
            case .debugWorkspace(let id, let identity, let source):
                Task { [weak self] in
                    guard let self, let window = self.presentedWindow(id)?.info,
                          window.identity == identity, let editor = self.workspaceEditor(in: window) else { return }
                    await self.debugWorkspace(windowID: id, editorID: editor.id, preparedSource: source)
                }
            }
        }
    }

    private func scheduleInputSynchronization() {
        inputDebounce?.cancel()
        guard hasLoaded, !isRunning, !windowPresentation.isRecovering, controlEdits.hasLiveEdits else { return }
        inputDebounce = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(80)) } catch { return }
            guard let self, !self.isRunning else { return }
            _ = await self.synchronizeInputs()
        }
    }

    /// Join an in-flight live edit before running a command. Typing itself never
    /// toggles isRunning, so changing the model does not disable the focused field.
    private func synchronizeInputs() async -> Bool {
        while true {
            // Retained editor drafts are evaluated directly during recovery;
            // their old Smalltalk window may no longer be reachable.
            if windowPresentation.isRecovering { return true }
            if let running = inputFlush {
                let success = await running.task.value
                if inputFlush?.id == running.id { inputFlush = nil }
                if !success { return false }
            } else if !controlEdits.hasPendingEdits {
                return true
            } else {
                let id = UUID()
                let task = Task { [weak self] in await self?.performInputFlush() ?? true }
                inputFlush = (id, task)
            }
        }
    }

    private func performInputFlush() async -> Bool {
        let epoch = inputEpoch
        var latestInput: EvaluationResult?
        var failures: [Int64: String] = [:]
        var editedWindows: Set<Int64> = []
        var acknowledged: [ControlEdits.TextEdit] = []
        for edit in controlEdits.pendingEdits {
            let address = edit.address
            // Editors must remain usable for repairing a rejected form input.
            if !failures.isEmpty && !controlEdits.isCodeEditor(address) { continue }
            let evaluation = await session.uiAction(.text(windowID: address.windowID, elementID: address.elementID, value: edit.text))
            guard inputEpoch == epoch else { return true }
            latestInput = evaluation
            editedWindows.insert(address.windowID)
            if let error = evaluation.executionError {
                failures[address.windowID] = error
            } else {
                acknowledged.append(edit)
            }
            if !evaluation.toolRequests.isEmpty { apply(evaluation) }
        }
        // Publish the acknowledged text before releasing the native draft.
        // An editor can redraw from an older projected element in the meantime.
        if let latestInput { apply(latestInput) }
        if !windowPresentation.isRecovering {
            for edit in acknowledged { controlEdits.acknowledge(edit) }
        }
        for id in editedWindows { windowPresentation.setInputError(failures[id], for: id) }
        return failures.isEmpty
    }

    /// Flush local edits before evaluating Smalltalk or taking an image snapshot.
    @discardableResult
    private func flushWindowState(allowInputFailure: Bool = false) async -> Bool {
        nativeWindows?.captureGeometry()
        let windowsValid = await synchronizeWindowEvents()
        guard windowsValid || allowInputFailure else { return false }
        return await synchronizeInputs() || allowInputFailure
    }

    func sourceHighlights(_ source: String) async -> [SourceHighlight] {
        await session.sourceHighlights(source)
    }

    func editorSelection(windowID: Int64, elementID: String) -> NSRange {
        controlEdits.selection(at: ControlAddress(windowID: windowID, elementID: elementID))
    }

    func setEditorSelection(_ range: NSRange, windowID: Int64, elementID: String) {
        controlEdits.recordSelection(range, at: ControlAddress(windowID: windowID, elementID: elementID))
    }

    private func activeButton(for command: String) -> (windowID: Int64, button: UIElementInfo)? {
        guard keyInspectorID == nil, let window = windowPresentation.activeWindow?.info,
              let button = window.content?.firstVisible(where: { $0.command == command && $0.enabled }),
              canPerform(button, in: window.id) else { return nil }
        return (window.id, button)
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
        // Class definitions and new methods already get their enabled state from Smalltalk.
        guard element.command == "acceptMethod", let window = presentedWindow(windowID)?.info,
              let compiled = window.browserMethodSource,
              let editor = window.content?.firstVisible(where: { $0.accessibilityID == "methodEditor" }) else { return true }
        return inputText(windowID: windowID, element: editor) != compiled
    }

    private func workspaceEditor(in window: ToolWindowInfo) -> UIElementInfo? {
        guard window.kind == .workspace else { return nil }
        return window.content?.firstVisible {
            $0.kind == .codeEditor && $0.accessibilityID == "workspaceEditor" && $0.enabled
        }
    }

    private func legacyWorkspaceEditor(in window: ToolWindowInfo) -> UIElementInfo? {
        guard let editor = workspaceEditor(in: window), editor.contextMenuItems == nil else { return nil }
        return editor
    }

    var canInspectWorkspace: Bool {
        guard keyInspectorID == nil, let window = windowPresentation.activeWindow?.info else { return false }
        return hasCommand("inspectIt") || legacyWorkspaceEditor(in: window) != nil
    }

    func editorContextItems(windowID: Int64, editor: UIElementInfo) -> [EditorContextItem] {
        let window = presentedWindow(windowID)?.info
        let isWorkspaceEditor = window.flatMap { workspaceEditor(in: $0) }?.id == editor.id
        if windowPresentation.isRecovering {
            guard isWorkspaceEditor, let window else { return [] }
            return ["doIt", "printIt", "inspectIt"].compactMap { command in
                window.content?.firstVisible(where: { $0.command == command && $0.selectionSource == editor.id })
                    .flatMap(EditorContextItem.init(projected:))
            }
        }
        var items: [EditorContextItem]
        if let projected = editor.contextMenuItems {
            items = projected.compactMap(EditorContextItem.init(projected:))
            guard !items.isEmpty, !projected.contains(where: { $0.command == "debugIt" }) else { return items }
        } else if isWorkspaceEditor, let window {
            // An older image already defines the first two commands on its toolbar.
            items = ["doIt", "printIt"].compactMap { command in
                window.content?.firstVisible(where: { $0.command == command && $0.selectionSource == editor.id })
                    .flatMap(EditorContextItem.init(projected:))
            }
            items.append(.command(title: "Inspect it", identifier: "inspectIt", action: .legacyInspect, enabled: true))
        } else {
            return []
        }
        if isWorkspaceEditor {
            items.append(.command(title: "Debug it", identifier: "debugIt",
                                  action: .debugWorkspace(editorID: editor.id), enabled: true))
        }
        return items
    }

    func performEditorContextAction(_ action: EditorContextAction, windowID: Int64, selection: String? = nil) async {
        switch action {
        case .control(let id):
            await clickControl(windowID: windowID, elementID: id, selection: selection)
        case .legacyInspect:
            await inspectLegacyWorkspace(windowID: windowID, capturedSelection: selection)
        case .debugWorkspace(let editorID):
            await debugWorkspace(windowID: windowID, editorID: editorID, capturedSelection: selection)
        }
    }

    var canDebugWorkspace: Bool {
        guard !isRunning, !windowPresentation.isRecovering, keyInspectorID == nil,
              let window = windowPresentation.activeWindow?.info else {
            return false
        }
        return workspaceEditor(in: window) != nil
    }

    func debugWorkspace() async {
        guard canDebugWorkspace, let window = windowPresentation.activeWindow?.info,
              let editor = workspaceEditor(in: window) else { return }
        if hasCommand("debugIt") {
            await performCommand("debugIt")
        } else {
            await debugWorkspace(windowID: window.id, editorID: editor.id)
        }
    }

    func stopDebugging() {
        debuggerStopRequested = true
        debugSession?.send(.stop)
    }

    private func debugWorkspace(windowID: Int64, editorID: String, capturedSelection: String? = nil,
                                preparedSource: String? = nil) async {
        guard !isRunning, let window = presentedWindow(windowID)?.info,
              let editor = workspaceEditor(in: window), editor.id == editorID else { return }
        let text = inputText(windowID: windowID, element: editor)
        let selected = capturedSelection ?? selectedText(in: editor, windowID: windowID, text: text)
        let source = preparedSource ?? (selected.isEmpty ? text : selected)
        let debuggerWindowID = UUID()
        var presentation: DebuggerPresentationState?
        debuggerStopRequested = false
        isRunning = true
        defer {
            presentation?.cancel()
            nativeWindows?.closeTransientWindow(debuggerWindowID)
            debugSession = nil
            isRunning = false
        }
        guard await flushWindowState(allowInputFailure: true), !debuggerStopRequested,
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
                apply(evaluation)
                windowPresentation.setInputError(evaluation.error, for: windowID)
                imageHasChanges = true
                return
            }
        }
    }

    private func openInspector(_ snapshot: InspectorSnapshot) {
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

    private func closeInspector(_ id: UUID) {
        guard let state = inspectors.removeValue(forKey: id) else { return }
        if keyInspectorID == id { keyInspectorID = nil }
        nativeWindows?.closeTransientWindow(id)
        state.close()
    }

    func inspectWorkspace() async {
        guard !isRunning, keyInspectorID == nil else { return }
        if hasCommand("inspectIt") {
            await performCommand("inspectIt")
            return
        }
        guard let windowID = windowPresentation.activeWindow?.info.id else { return }
        await inspectLegacyWorkspace(windowID: windowID)
    }

    private func inspectLegacyWorkspace(windowID: Int64, capturedSelection: String? = nil) async {
        guard !isRunning, let window = presentedWindow(windowID)?.info,
              let editor = legacyWorkspaceEditor(in: window) else { return }
        let text = inputText(windowID: windowID, element: editor)
        let selected = capturedSelection ?? selectedText(in: editor, windowID: windowID, text: text)
        let source = selected.isEmpty ? text : selected
        isRunning = true
        defer { isRunning = false }
        guard await flushWindowState(allowInputFailure: true) else { return }
        guard let current = presentedWindow(windowID)?.info, legacyWorkspaceEditor(in: current)?.id == editor.id else { return }
        let evaluation = await session.inspectSource(source)
        apply(evaluation)
        windowPresentation.setInputError(evaluation.error, for: windowID)
        imageHasChanges = true
    }

    func inputText(windowID: Int64, element: UIElementInfo) -> String {
        controlEdits.text(at: ControlAddress(windowID: windowID, elementID: element.id), fallback: element.text)
    }

    func editInput(windowID: Int64, elementID: String, text: String) {
        controlEdits.recordText(text, at: ControlAddress(windowID: windowID, elementID: elementID))
        imageHasChanges = true
        scheduleInputSynchronization()
    }

    func clickControl(windowID: Int64, elementID: String, selection capturedSelection: String? = nil) async {
        guard let window = presentedWindow(windowID)?.info,
              let root = window.content, let button = root.firstVisible(where: { $0.id == elementID }),
              canPerform(button, in: windowID) else { return }
        let selection = capturedSelection ?? selectedText(for: button, in: windowID, root: root)
        if windowPresentation.isRecovering, window.kind == .workspace,
           let command = button.command, let action = WorkspaceRecoveryAction(command: command),
           let editor = workspaceEditor(in: window) {
            await recoverWorkspace(window, editor: editor, action: action, selection: selection)
            return
        }
        let acceptsRejectedInput = window.kind == .workspace || window.kind == .browser
        await sendControl(.click(windowID: windowID, elementID: elementID, selection: selection),
                          windowID: windowID, allowInputFailure: acceptsRejectedInput)
    }

    private func recoverWorkspace(_ window: ToolWindowInfo, editor: UIElementInfo,
                                  action: WorkspaceRecoveryAction, selection: String) async {
        guard !isRunning, let currentEpoch else { return }
        let source = selection.isEmpty ? inputText(windowID: window.id, element: editor) : selection
        isRunning = true
        defer { isRunning = false }
        let evaluation = await session.recoverWorkspace(source: source, action: action, windowID: window.id,
                                                        identity: window.identity, epoch: currentEpoch)
        apply(evaluation)
        windowPresentation.setInputError(evaluation.executionError, for: window.id)
        if windowPresentation.isRecovering {
            windowPresentation.setRecoveryResult(evaluation.value, for: window.id)
        }
        imageHasChanges = true
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
        await sendControl(.select(windowID: windowID, elementID: elementID, value: value), windowID: windowID, allowInputFailure: true)
    }

    private func sendControl(_ action: UIAction, windowID: Int64, allowInputFailure: Bool) async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        guard await flushWindowState(allowInputFailure: allowInputFailure) else { return }
        let evaluation = await session.uiAction(action)
        apply(evaluation)
        windowPresentation.setInputError(evaluation.error, for: windowID)
        imageHasChanges = true
    }

    func openTool(_ kind: ToolKind) async { await sendWindowAction(.open(kind)) }

    func showWorkspace() async {
        if windowPresentation.isRecovering, let workspace = windowPresentation.workspace {
            windowPresentation.activeID = workspace.info.id
            nativeWindows?.activateWindowForRecovery(workspace.info.id, identity: workspace.info.identity)
            return
        }
        await sendWindowAction(.showWorkspace)
    }

    var canClearTranscript: Bool { transcriptClearControl != nil }

    func clearTranscript() async {
        guard let target = transcriptClearControl else { return }
        await clickControl(windowID: target.windowID, elementID: target.buttonID)
    }

    private var transcriptClearControl: (windowID: Int64, buttonID: String)? {
        guard let transcript = windowPresentation.windows.last(where: { $0.info.kind == .transcript }),
              let button = transcript.info.content?.firstVisible(where: { $0.command == "clearTranscript" && $0.enabled })
        else { return nil }
        return (transcript.info.id, button.id)
    }

    func arrangeTools() async { await sendWindowAction(.arrangeTools) }

    private func sendWindowAction(_ action: WindowAction) async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        guard await flushWindowState(allowInputFailure: true) else { return }
        apply(await session.windowAction(action))
        imageHasChanges = true
    }

    func reset() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        guard await confirmSessionReplacement(.reset) else { return }
        // Join outstanding native input before replacing its interpreter world.
        await flushWindowState(allowInputFailure: true)
        do {
            let replacement = try await session.reset(startingChangeLogAt: unsavedChangeLogURL())
            clearPending()
            persistenceError = nil
            apply(replacement, replacingWindows: true)
            await arrangeInitialTools()
            imageURL = nil; imageHasChanges = false
        } catch {
            persistenceError = "Could not reset the session: \(error.localizedDescription)"
        }
    }

    func openWorkspace() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, UTType(filenameExtension: "st") ?? .plainText]
        panel.allowsOtherFileTypes = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let source = try String(contentsOf: url, encoding: .utf8)
            guard await flushWindowState(allowInputFailure: true) else { return }
            let opened = await session.windowAction(.open(.workspace))
            let workspaceID = opened.activeWindowID
            let wasOpen = workspaceID.flatMap { presentedWindow($0) } != nil
            apply(opened)
            guard opened.executionError == nil, !wasOpen, let workspaceID,
                  presentedWindow(workspaceID)?.info.kind == .workspace else { return }
            let loaded = await session.windowAction(.text(workspaceID, source))
            apply(loaded)
            if loaded.executionError == nil {
                windowPresentation.setDocumentURL(url, for: workspaceID)
                imageHasChanges = true
            }
        } catch { self.error = error.localizedDescription }
    }

    func saveWorkspace() async {
        guard !isRunning, let workspace = windowPresentation.workspace else { return }
        isRunning = true
        defer { isRunning = false }
        guard await flushWindowState(allowInputFailure: windowPresentation.isRecovering),
              let current = presentedWindow(workspace.info.id), current.info.identity == workspace.info.identity else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "st") ?? .plainText]
        panel.nameFieldStringValue = current.documentURL?.lastPathComponent ?? "Workspace.st"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let source = workspaceEditor(in: current.info).map { inputText(windowID: current.info.id, element: $0) }
                ?? current.info.text
            try source.write(to: url, atomically: true, encoding: .utf8)
            windowPresentation.setDocumentURL(url, for: current.info.id)
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    func openImage() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        let panel = NSOpenPanel()
        panel.title = "Open Smalltalk Image"
        panel.allowedContentTypes = [Self.imageType]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard await confirmSessionReplacement(.openImage) else { return }
        await flushWindowState(allowInputFailure: true)
        do {
            try await restoreImage(from: url)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not load the image"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    enum ImageSaveResult {
        case saved, cancelled, failed(String)
    }

    @discardableResult
    func saveImage(asNewFile: Bool = false) async -> ImageSaveResult {
        guard !isRunning else { return .cancelled }
        isRunning = true
        defer { isRunning = false }
        return await saveImageWhileRunning(asNewFile: asNewFile)
    }

    private func saveImageWhileRunning(asNewFile: Bool = false) async -> ImageSaveResult {
        let url: URL
        if let imageURL, !asNewFile { url = imageURL }
        else {
            let panel = NSSavePanel()
            panel.title = "Save Smalltalk Image"
            panel.allowedContentTypes = [Self.imageType]
            panel.nameFieldStringValue = imageURL?.lastPathComponent ?? "Smalltalk.stimage"
            panel.directoryURL = imageURL?.deletingLastPathComponent()
            guard panel.runModal() == .OK, let chosen = panel.url else { return .cancelled }
            url = chosen
        }
        guard await flushWindowState() else {
            let reason = error ?? windowPresentation.windows.compactMap(\.inputError).first
            return .failed(reason ?? "Some pending window or editor changes could not be applied.")
        }
        do {
            try await session.saveImage(to: url, workspace: windowPresentation.workspace?.info.text ?? "", transcript: "")
            apply(await session.snapshot())
            imageURL = url
            imageHasChanges = controlEdits.hasPendingEdits || !pendingWindowEvents.isEmpty
            persistenceError = nil
            error = nil
            return .saved
        } catch {
            self.error = "Could not save the image: \(error.localizedDescription)"
            return .failed(error.localizedDescription)
        }
    }

    private func clearPending() {
        windowDebounce?.cancel()
        windowDebounce = nil
        inputEpoch += 1
        inputDebounce?.cancel()
        inputDebounce = nil
        windowEpoch += 1
        pendingWindowEvents.removeAll()
        controlEdits = ControlEdits()
    }

    private enum SessionReplacement {
        case quit, reset, openImage

        var consequence: String {
            switch self {
            case .quit: "quit"
            case .reset: "reset the session"
            case .openImage: "open another image"
            }
        }
    }

    func confirmQuit() async -> Bool {
        guard !isRunning else { return false }
        isRunning = true
        defer { isRunning = false }
        return await confirmSessionReplacement(.quit)
    }

    /// All callers hold isRunning, including while native save panels are open.
    private func confirmSessionReplacement(_ action: SessionReplacement) async -> Bool {
        guard imageNeedsSaving() else { return true }
        let alert = NSAlert()
        alert.messageText = "Save changes to the Smalltalk image?"
        alert.informativeText = "Your changes since the last save will be lost if you \(action.consequence) without saving."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"
        alert.addButton(withTitle: "Don't Save")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            switch await saveImageWhileRunning() {
            case .saved: return !imageNeedsSaving()
            case .cancelled: return false
            case .failed(let reason):
                let failure = NSAlert()
                failure.messageText = "Could not save the image"
                failure.informativeText = reason
                failure.runModal()
                return false
            }
        case .alertThirdButtonReturn: return true
        default: return false
        }
    }

    private func startUnsavedChangeLog() async throws {
        try await session.startChangeLog(at: unsavedChangeLogURL())
    }

    private func unsavedChangeLogURL() throws -> URL {
        let base: URL
        if let suite = ProcessInfo.processInfo.environment["ST80_PREFERENCES_SUITE"] {
            // UI tests run in a different sandbox from the app. An explicit
            // directory lets them exercise actual journal I/O failures.
            base = ProcessInfo.processInfo.environment["ST80_CHANGES_DIRECTORY"].map {
                URL(fileURLWithPath: $0, isDirectory: true)
            } ?? FileManager.default.temporaryDirectory.appendingPathComponent("st80-changes-" + suite)
        } else {
            base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("Smalltalk80/Changes")
        }
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent(UUID().uuidString + ".changes")
    }

    func showChanges(className: String? = nil, selector: String? = nil, side: MethodSide = .instance) async {
        await sendWindowAction(.showChanges(className: className, selector: selector, side: side))
    }

    func openChanges() async {
        guard !isRunning else { return }
        let panel = NSOpenPanel()
        panel.title = "Open Changes Log for Recovery"
        panel.allowedContentTypes = [UTType(filenameExtension: "changes") ?? .plainText]
        panel.directoryURL = changesPath.map { URL(fileURLWithPath: $0).deletingLastPathComponent() }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        isRunning = true
        do { apply(try await session.importChanges(from: url)) }
        catch { self.error = error.localizedDescription }
        isRunning = false
        await showChanges()
    }
    private func restoreImage(from url: URL) async throws {
        let image = try await session.loadImage(from: url)
        clearPending()
        persistenceError = nil
        apply(image.evaluation, replacingWindows: true)
        imageURL = url; imageHasChanges = false
        error = nil
    }
}
