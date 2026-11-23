import AppKit
import SmalltalkCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class AppController {
    private var windowPresentation = WindowPresentation()
    private var controlEdits = ControlEdits()
    var result = "Ready."
    var error: String?
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
    @ObservationIgnored private lazy var inspectorWindows = NativeInspectorWindows(session: session)
    private let preferences: UserDefaults
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
    var changes: [ChangeInfo] = []
    var savedChangeSequence: Int64 = 0
    var changesPath: String?
    var changeClassFilter: String?
    var changeMethodFilter: String?
    var changeSideFilter: MethodSide?
    var selectedChange: String?
    var baseChange: ChangeInfo?
    @ObservationIgnored private var nativeWindows: NativeWindowBackend?
    private static let lastImageKey = "lastImagePath"
    private static var imageType: UTType { UTType(filenameExtension: "stimage", conformingTo: .data) ?? .data }

    init() {
        let suite = ProcessInfo.processInfo.environment["ST80_PREFERENCES_SUITE"]
        preferences = suite.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    var activeKind: ToolKind? { windowPresentation.activeWindow?.info.kind }

    func presentedWindow(_ id: Int64) -> PresentedWindow? { windowPresentation.window(id) }

    func load() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        nativeWindows = NativeWindowBackend(
            content: { [weak self] id in
                guard let self else { return AnyView(EmptyView()) }
                return AnyView(ToolContentView(controller: self, windowID: id))
            },
            onEvent: { [weak self] event in self?.received(event) }
        )
        isRunning = true
        defer { isRunning = false }
        if let path = preferences.string(forKey: Self.lastImageKey) {
            do { try await restoreImage(from: URL(fileURLWithPath: path)); return }
            catch { self.error = "Could not load the last image: \(error.localizedDescription)" }
        }
        do { try await startUnsavedChangeLog() } catch { self.error = error.localizedDescription }
        let failure = error
        apply(await session.snapshot(), replacingWindows: true)
        await arrangeInitialTools()
        error = failure
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
                    inspectorWindows.open(snapshot)
                }
                return
            }
            guard evaluation.windowCommands.revision > latestRevision else { return }
        }
        currentEpoch = evaluation.windowCommands.epoch
        latestRevision = evaluation.windowCommands.revision
        if replacingWindows { inspectorWindows.closeAll() }
        changes = evaluation.changes
        savedChangeSequence = evaluation.savedChangeSequence
        changesPath = evaluation.changesPath
        error = evaluation.error
        if let value = evaluation.value { result = value }
        windowPresentation.update(from: evaluation, replacingWindows: replacingWindows)
        controlEdits.reconcile(with: evaluation.windows)
        nativeWindows?.execute(evaluation.windowCommands)
        for request in evaluation.toolRequests {
            switch request {
            case .saveImage:
                Task { [weak self] in await self?.saveImage() }
            case .showVersions(let className, let selector, let side):
                Task { [weak self] in await self?.showChanges(className: className, selector: selector, side: side) }
            case .openInspector(let snapshot):
                inspectorWindows.open(snapshot)
            }
        }
    }

    private func scheduleInputSynchronization() {
        inputDebounce?.cancel()
        guard hasLoaded, !isRunning, controlEdits.hasLiveEdits else { return }
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
        for edit in acknowledged { controlEdits.acknowledge(edit) }
        if let latestInput { apply(latestInput) }
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

    func editorSelection(windowID: Int64, elementID: String) -> NSRange {
        controlEdits.selection(at: ControlAddress(windowID: windowID, elementID: elementID))
    }

    func setEditorSelection(_ range: NSRange, windowID: Int64, elementID: String) {
        controlEdits.recordSelection(range, at: ControlAddress(windowID: windowID, elementID: elementID))
    }

    private func activeButton(for command: String) -> (windowID: Int64, button: UIElementInfo)? {
        guard !inspectorWindows.hasKeyWindow, let window = windowPresentation.activeWindow,
              !(command == "acceptMethod" && window.showsBytecode),
              let button = window.info.content?.firstVisible(where: { $0.command == command && $0.enabled }) else { return nil }
        return (window.info.id, button)
    }

    func hasCommand(_ command: String) -> Bool { activeButton(for: command) != nil }

    func performCommand(_ command: String) async {
        guard let target = activeButton(for: command) else { return }
        await clickControl(windowID: target.windowID, elementID: target.button.id)
    }

    func toggleBrowserBytecode(windowID: Int64) {
        guard !isRunning else { return }
        windowPresentation.toggleBytecode(for: windowID)
    }

    func browserBytecode(windowID: Int64, method: BrowserMethodSelection) async -> String? {
        await session.browserBytecode(windowID: windowID, method: method)
    }

    private func legacyWorkspaceEditor(in window: ToolWindowInfo) -> UIElementInfo? {
        guard window.kind == .workspace,
              let editor = window.content?.firstVisible(where: { $0.accessibilityID == "workspaceEditor" && $0.enabled }),
              editor.contextMenuItems == nil else {
            return nil
        }
        return editor
    }

    var canInspectWorkspace: Bool {
        guard !inspectorWindows.hasKeyWindow, let window = windowPresentation.activeWindow?.info else { return false }
        return hasCommand("inspectIt") || legacyWorkspaceEditor(in: window) != nil
    }

    func editorContextItems(windowID: Int64, editor: UIElementInfo) -> [EditorContextItem] {
        if let items = editor.contextMenuItems { return items.compactMap(EditorContextItem.init(projected:)) }
        // An older image already defines the first two commands on its toolbar.
        guard let window = presentedWindow(windowID)?.info, legacyWorkspaceEditor(in: window)?.id == editor.id else {
            return []
        }
        var items = ["doIt", "printIt"].compactMap { command in
            window.content?.firstVisible(where: { $0.command == command && $0.selectionSource == editor.id })
                .flatMap(EditorContextItem.init(projected:))
        }
        items.append(.command(title: "Inspect it", identifier: "inspectIt", action: .legacyInspect, enabled: true))
        return items
    }

    func performEditorContextAction(_ action: EditorContextAction, windowID: Int64, selection: String) async {
        switch action {
        case .control(let id):
            await clickControl(windowID: windowID, elementID: id, selection: selection)
        case .legacyInspect:
            await inspectLegacyWorkspace(windowID: windowID, capturedSelection: selection)
        }
    }

    func inspectWorkspace() async {
        guard !isRunning, !inspectorWindows.hasKeyWindow else { return }
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
        guard let window = presentedWindow(windowID), let root = window.info.content,
              let button = root.firstVisible(where: { $0.id == elementID }),
              !(button.command == "acceptMethod" && window.showsBytecode) else { return }
        let selection = capturedSelection ?? selectedText(for: button, in: windowID, root: root)
        let acceptsRejectedInput = window.info.kind == .workspace || window.info.kind == .browser
        await sendControl(.click(windowID: windowID, elementID: elementID, selection: selection),
                          windowID: windowID, allowInputFailure: acceptsRejectedInput)
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

    func showWorkspace() async { await sendWindowAction(.showWorkspace) }

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
        clearPending()
        _ = await session.reset()
        do { try await startUnsavedChangeLog() } catch { self.error = error.localizedDescription }
        apply(await session.snapshot(), replacingWindows: true)
        await arrangeInitialTools()
        imageURL = nil; imageHasChanges = false
        preferences.removeObject(forKey: Self.lastImageKey)
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
        guard await flushWindowState(),
              let current = presentedWindow(workspace.info.id), current.info.identity == workspace.info.identity else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "st") ?? .plainText]
        panel.nameFieldStringValue = current.documentURL?.lastPathComponent ?? "Workspace.st"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try current.info.text.write(to: url, atomically: true, encoding: .utf8)
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
        do { try await restoreImage(from: url) }
        catch { self.error = "Could not load the image: \(error.localizedDescription)" }
    }

    enum ImageSaveResult {
        case saved, cancelled, failed(String)
    }

    @discardableResult
    func saveImage(asNewFile: Bool = false) async -> ImageSaveResult {
        guard !isRunning else { return .cancelled }
        isRunning = true
        defer { isRunning = false }
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
            imageURL = url; preferences.set(url.path, forKey: Self.lastImageKey)
            imageHasChanges = controlEdits.hasPendingEdits || !pendingWindowEvents.isEmpty
            result = "Saved image: \(url.lastPathComponent)"; error = nil
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

    private func startUnsavedChangeLog() async throws {
        let base: URL
        if let suite = ProcessInfo.processInfo.environment["ST80_PREFERENCES_SUITE"] {
            base = FileManager.default.temporaryDirectory.appendingPathComponent("st80-changes-" + suite)
        } else {
            base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("Smalltalk80/Changes")
        }
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try await session.startChangeLog(at: base.appendingPathComponent(UUID().uuidString + ".changes"))
    }

    var filteredChanges: [ChangeInfo] {
        let history = changes.reversed().filter {
            (changeClassFilter == nil || $0.className == changeClassFilter) &&
            (changeMethodFilter == nil || $0.selector == changeMethodFilter) &&
            (changeSideFilter == nil || $0.side == changeSideFilter)
        }
        if let baseChange, changeClassFilter == baseChange.className, changeMethodFilter == baseChange.selector,
           changeSideFilter == baseChange.side { return history + [baseChange] }
        return history
    }
    func showChanges(className: String? = nil, selector: String? = nil, side: MethodSide = .instance) async {
        changeClassFilter = className
        changeMethodFilter = selector
        changeSideFilter = selector == nil ? nil : side
        selectedChange = nil
        baseChange = nil
        if let className, let selector { baseChange = await session.baseVersion(of: selector, in: className, side: side) }
        await openTool(.changes)
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
    func restoreSelectedChange() async {
        guard !isRunning, let selectedChange else { return }
        isRunning = true; defer { isRunning = false }
        guard await flushWindowState(allowInputFailure: true) else { return }
        let evaluation = await session.restoreChange(selectedChange)
        apply(evaluation)
        if evaluation.executionError == nil { imageHasChanges = true }
    }

    private func restoreImage(from url: URL) async throws {
        let image = try await session.loadImage(from: url)
        clearPending()
        apply(image.evaluation, replacingWindows: true)
        imageURL = url; imageHasChanges = false
        preferences.set(url.path, forKey: Self.lastImageKey)
        result = "Loaded image: \(url.lastPathComponent)"; error = nil
    }
}
