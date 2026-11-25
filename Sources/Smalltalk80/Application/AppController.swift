import AppKit
import SmalltalkCore
import SwiftUI

@MainActor
@Observable
final class AppController {
    private(set) var windowPresentation = WindowPresentation()
    private var controlEdits = ControlEdits()
    private var operationError: String?
    private var projectionError: String?
    var persistenceError: String?
    var error: String? {
        get {
            var seen: Set<String> = []
            let messages = [projectionError, operationError, persistenceError].compactMap { $0 }
                .filter { seen.insert($0).inserted }
            return messages.isEmpty ? nil : messages.joined(separator: "\n")
        }
        set { operationError = newValue }
    }
    private(set) var isRunning = false {
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
    private(set) var imageURL: URL?
    private var imageHasChanges = false
    let session = SmalltalkSession()
    @ObservationIgnored var inspectors: [UUID: InspectorPresentationState] = [:]
    var keyInspectorID: UUID?
    @ObservationIgnored var debugSession: WorkspaceDebugSession?
    @ObservationIgnored var debuggerStopRequested = false
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
    private(set) var changesPath: String?
    @ObservationIgnored private(set) var nativeWindows: NativeWindowBackend?

    var activeKind: ToolKind? { windowPresentation.activeWindow?.info.kind }
    var activeWindowID: Int64? { windowPresentation.activeID }
    var workspaceWindow: ToolWindowInfo? { windowPresentation.workspace?.info }
    var workspaceAppMenus: [UIElementInfo] {
        workspaceWindow?.content?.children.filter { $0.role == "applicationMenu" && $0.visible } ?? []
    }

    func presentedWindow(_ id: Int64) -> PresentedWindow? { windowPresentation.window(id) }

    func load() async {
        guard !hasLoaded else { return }
        await runOperation {
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
            do { try await startUnsavedChangeLog() }
            catch { persistenceError = "Changes cannot be recorded on disk: \(error.localizedDescription)" }
            apply(await session.snapshot(), replacingWindows: true)
            await arrangeInitialTools()
        }
    }

    func arrangeInitialTools() async {
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

    /// Run one foreground command at a time. Live edits and window events
    /// have their own synchronization and can be flushed by the command.
    @discardableResult
    func runOperation<Result>(_ operation: @MainActor () async -> Result) async -> Result? {
        guard !isRunning else { return nil }
        isRunning = true
        defer { isRunning = false }
        return await operation()
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

    func apply(_ evaluation: EvaluationResult, replacingWindows: Bool = false) {
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
            closeInspectors()
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
        var ignored: Set<ControlAddress> = []
        for edit in controlEdits.pendingEdits {
            let address = edit.address
            // Editors must remain usable for repairing a rejected form input.
            if !failures.isEmpty && !controlEdits.isCodeEditor(address) { continue }
            let result = await session.dispatchUIAction(.text(windowID: address.windowID, elementID: address.elementID, value: edit.text))
            guard inputEpoch == epoch else { return true }
            let evaluation = result.evaluation
            latestInput = evaluation
            editedWindows.insert(address.windowID)
            switch result.disposition {
            case .applied: acknowledged.append(edit)
            case .ignored: ignored.insert(address)
            case .rejected(let reason): failures[address.windowID] = reason
            }
            if !evaluation.toolRequests.isEmpty { apply(evaluation) }
        }
        // Publish the acknowledged text before releasing the native draft.
        // An editor can redraw from an older projected element in the meantime.
        if let latestInput { apply(latestInput) }
        if !windowPresentation.isRecovering {
            for edit in acknowledged { controlEdits.acknowledge(edit) }
        }
        // Reconciliation drops drafts whose controls were removed. A control
        // that still exists may accept its draft on a later flush.
        for address in ignored where controlEdits.hasDraft(at: address) && failures[address.windowID] == nil {
            failures[address.windowID] = "The control could not accept its pending edit. The draft is still available."
        }
        for id in editedWindows { windowPresentation.setInputError(failures[id], for: id) }
        return failures.isEmpty
    }

    /// Stop if the image rejects a window event or a pending editor change.
    func flushWindowStateRequiringSuccess() async -> Bool {
        nativeWindows?.captureGeometry()
        guard await synchronizeWindowEvents() else { return false }
        return await synchronizeInputs()
    }

    /// Try both queues before a command that can proceed with a rejected edit or event.
    func attemptToFlushWindowState() async {
        nativeWindows?.captureGeometry()
        _ = await synchronizeWindowEvents()
        _ = await synchronizeInputs()
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

    func inputText(windowID: Int64, element: UIElementInfo) -> String {
        controlEdits.text(at: ControlAddress(windowID: windowID, elementID: element.id), fallback: element.text)
    }

    func editInput(windowID: Int64, elementID: String, text: String) {
        controlEdits.recordText(text, at: ControlAddress(windowID: windowID, elementID: elementID))
        imageHasChanges = true
        scheduleInputSynchronization()
    }

    func recoverWorkspace(_ window: ToolWindowInfo, editor: UIElementInfo,
                          action: WorkspaceRecoveryAction, selection: String) async {
        guard let currentEpoch else { return }
        await runOperation {
            let source = selection.isEmpty ? inputText(windowID: window.id, element: editor) : selection
            let evaluation = await session.recoverWorkspace(source: source, action: action, windowID: window.id,
                                                            identity: window.identity, epoch: currentEpoch)
            apply(evaluation)
            windowPresentation.setInputError(evaluation.executionError, for: window.id)
            if windowPresentation.isRecovering {
                windowPresentation.setRecoveryResult(evaluation.value, for: window.id)
            }
            imageHasChanges = true
        }
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
        await runOperation {
            await attemptToFlushWindowState()
            apply(await session.windowAction(action))
            imageHasChanges = true
        }
    }

    func installReplacement(_ evaluation: EvaluationResult) {
        clearPending()
        persistenceError = nil
        apply(evaluation, replacingWindows: true)
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

    func showChanges(className: String? = nil, selector: String? = nil, side: MethodSide = .instance) async {
        await sendWindowAction(.showChanges(className: className, selector: selector, side: side))
    }

    func applyControlResult(_ evaluation: EvaluationResult, windowID: Int64) {
        apply(evaluation)
        windowPresentation.setInputError(evaluation.error, for: windowID)
        imageHasChanges = true
    }

    func associateWorkspace(_ windowID: Int64, with url: URL, afterOpening: Bool = false) {
        windowPresentation.setDocumentURL(url, for: windowID)
        if afterOpening { imageHasChanges = true }
    }

    func setSavedImageURL(_ url: URL?, includingPendingEdits: Bool = false) {
        imageURL = url
        imageHasChanges = includingPendingEdits && (controlEdits.hasPendingEdits || !pendingWindowEvents.isEmpty)
    }
}
