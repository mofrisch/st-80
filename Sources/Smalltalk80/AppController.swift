import AppKit
import SmalltalkCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class ToolWindowState {
    let id: Int64
    let kind: ToolKind
    let identity: String
    var text: String
    var documentURL: URL?
    var error: String?
    var content: UIElementInfo?

    init(_ info: ToolWindowInfo) {
        id = info.id
        kind = info.kind
        identity = info.identity
        text = info.text
        content = info.content
    }
}

@MainActor
@Observable
final class AppController {
    var states: [Int64: ToolWindowState] = [:]
    var windowInfos: [ToolWindowInfo] = []
    var activeWindowID: Int64?
    var result = "Bereit."
    var error: String?
    var isRunning = false {
        didSet {
            if !isRunning { scheduleSynchronization(); scheduleInputSynchronization() }
        }
    }
    var imageURL: URL?
    var imageHasChanges = true
    private let session = SmalltalkSession()
    private let preferences: UserDefaults
    private var hasLoaded = false
    private struct InputAddress: Hashable {
        let windowID: Int64
        let elementID: String
    }
    private var editorSelections: [InputAddress: NSRange] = [:]
    private var pendingInputs: [InputAddress: String] = [:]
    private var inputOrder: [InputAddress: UInt64] = [:]
    @ObservationIgnored private var inputSequence: UInt64 = 0
    private var liveInputs: Set<InputAddress> = []
    @ObservationIgnored private var inputDebounce: Task<Void, Never>?
    @ObservationIgnored private var inputFlush: (id: UUID, task: Task<Bool, Never>)?
    @ObservationIgnored private var inputEpoch = 0
    private var pendingWindowEvents: [NativeWindowEvent] = []
    @ObservationIgnored private var windowFlush: (id: UUID, task: Task<Bool, Never>)?
    @ObservationIgnored private var windowEpoch = 0
    private var synchronization: Task<Void, Never>?
    private var currentEpoch: String?
    private var latestRevision: Int64 = 0
    var changes: [ChangeInfo] = []
    var savedChangeSequence: Int64 = 0
    var changesPath: String?
    var changeClassFilter: String?
    var changeMethodFilter: String?
    var selectedChange: String?
    var baseChange: ChangeInfo?
    @ObservationIgnored private var nativeWindows: NativeWindowBackend?
    private static let lastImageKey = "lastImagePath"
    private static var imageType: UTType { UTType(filenameExtension: "stimage", conformingTo: .data) ?? .data }

    init() {
        let suite = ProcessInfo.processInfo.environment["ST80_PREFERENCES_SUITE"]
        preferences = suite.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    var activeKind: ToolKind? { activeWindowID.flatMap { states[$0]?.kind } }
    var workspaceState: ToolWindowState? {
        if let id = activeWindowID, let state = states[id], state.kind == .workspace { return state }
        return windowInfos.last(where: { $0.kind == .workspace }).flatMap { states[$0.id] }
    }
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
            catch { self.error = "Das letzte Image konnte nicht geladen werden: \(error.localizedDescription)" }
        }
        do { try await startUnsavedChangeLog() } catch { self.error = error.localizedDescription }
        let failure = error
        apply(await session.snapshot(), replaceBuffers: true)
        error = failure
    }

    private func received(_ event: NativeWindowEvent) {
        pendingWindowEvents.append(event)
        if case .activated(let id) = event.kind, states[id] != nil {
            activeWindowID = id
        }
        imageHasChanges = true
        scheduleSynchronization()
    }

    private func scheduleSynchronization() {
        guard hasLoaded, !isRunning, synchronization == nil, !pendingWindowEvents.isEmpty else { return }
        synchronization = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(40)) } catch { return }
            guard let self else { return }
            self.synchronization = nil
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

    private func apply(_ evaluation: EvaluationResult, replaceBuffers: Bool = false) {
        if !replaceBuffers, let currentEpoch {
            guard evaluation.windowCommands.epoch == currentEpoch, evaluation.windowCommands.revision > latestRevision else { return }
        }
        currentEpoch = evaluation.windowCommands.epoch; latestRevision = evaluation.windowCommands.revision
        changes = evaluation.changes; savedChangeSequence = evaluation.savedChangeSequence; changesPath = evaluation.changesPath
        error = evaluation.error
        if let value = evaluation.value { result = value }
        let previous = windowInfos
        let ids = Set(evaluation.windows.map(\.id))
        states = states.filter { ids.contains($0.key) }
        for info in evaluation.windows {
            if let state = states[info.id], state.kind == info.kind, state.identity == info.identity, !replaceBuffers {
                state.text = info.text
                state.content = info.content
            } else {
                states[info.id] = ToolWindowState(info)
            }
        }
        var visibleInputs: Set<InputAddress> = []
        var visibleLiveInputs: Set<InputAddress> = []
        var visibleEditors: Set<InputAddress> = []
        func collectInputs(_ node: UIElementInfo, windowID: Int64) {
            if node.kind == .textField || node.kind == .codeEditor {
                let address = InputAddress(windowID: windowID, elementID: node.id)
                visibleInputs.insert(address)
                if node.liveInput { visibleLiveInputs.insert(address) }
                if node.kind == .codeEditor {
                    visibleEditors.insert(address)
                    let oldRoot = previous.first { $0.id == windowID }?.content
                    if pendingInputs[address] == nil, let old = element(in: oldRoot, where: { $0.id == node.id }),
                       old.text != node.text, let selection = editorSelections[address],
                       NSMaxRange(selection) > (node.text as NSString).length {
                        editorSelections.removeValue(forKey: address)
                    }
                }
            }
            for child in node.children { collectInputs(child, windowID: windowID) }
        }
        for info in evaluation.windows {
            if let content = info.content { collectInputs(content, windowID: info.id) }
        }
        pendingInputs = pendingInputs.filter { visibleInputs.contains($0.key) }
        inputOrder = inputOrder.filter { visibleInputs.contains($0.key) }
        liveInputs = visibleLiveInputs
        editorSelections = editorSelections.filter { visibleEditors.contains($0.key) }
        windowInfos = evaluation.windows
        activeWindowID = evaluation.activeWindowID
        nativeWindows?.execute(evaluation.windowCommands)
        for request in evaluation.toolRequests {
            Task { [weak self] in
                guard let self else { return }
                switch request {
                case .saveImage: await self.saveImage()
                case .showVersions(let className, let selector): await self.showChanges(className: className, selector: selector)
                }
            }
        }
    }

    private func scheduleInputSynchronization() {
        inputDebounce?.cancel()
        guard hasLoaded, !isRunning, pendingInputs.keys.contains(where: { liveInputs.contains($0) }) else { return }
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
            } else if pendingInputs.isEmpty {
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
        var acknowledged: [(InputAddress, String)] = []
        for (address, text) in pendingInputs.sorted(by: { (inputOrder[$0.key] ?? 0) < (inputOrder[$1.key] ?? 0) }) {
            // Editors must remain usable for repairing a rejected form input.
            if !failures.isEmpty {
                let control = element(in: states[address.windowID]?.content, where: { $0.id == address.elementID })
                if control?.kind != .codeEditor { continue }
            }
            let evaluation = await session.uiAction(.text(windowID: address.windowID, elementID: address.elementID, value: text))
            guard inputEpoch == epoch else { return true }
            latestInput = evaluation
            editedWindows.insert(address.windowID)
            if let error = evaluation.executionError {
                failures[address.windowID] = error
            } else {
                acknowledged.append((address, text))
            }
            if !evaluation.toolRequests.isEmpty { apply(evaluation) }
        }
        for (address, text) in acknowledged where pendingInputs[address] == text {
            pendingInputs.removeValue(forKey: address)
            inputOrder.removeValue(forKey: address)
        }
        if let latestInput { apply(latestInput) }
        for id in editedWindows { states[id]?.error = failures[id] }
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

    private func element(in root: UIElementInfo?, where predicate: (UIElementInfo) -> Bool) -> UIElementInfo? {
        guard let root, root.visible else { return nil }
        if predicate(root) { return root }
        for child in root.children {
            if let found = element(in: child, where: predicate) { return found }
        }
        return nil
    }

    func editorSelection(windowID: Int64, elementID: String) -> NSRange {
        editorSelections[InputAddress(windowID: windowID, elementID: elementID)] ?? NSRange(location: 0, length: 0)
    }

    func setEditorSelection(_ range: NSRange, windowID: Int64, elementID: String) {
        let address = InputAddress(windowID: windowID, elementID: elementID)
        if editorSelections[address] != range { editorSelections[address] = range }
    }

    func hasCommand(_ command: String) -> Bool {
        guard let id = activeWindowID else { return false }
        return element(in: states[id]?.content, where: { $0.command == command && $0.enabled }) != nil
    }

    func performCommand(_ command: String) async {
        guard let id = activeWindowID,
              let button = element(in: states[id]?.content, where: { $0.command == command && $0.enabled }) else { return }
        await clickControl(windowID: id, elementID: button.id)
    }

    func inputText(windowID: Int64, element: UIElementInfo) -> String {
        pendingInputs[InputAddress(windowID: windowID, elementID: element.id)] ?? element.text
    }

    func editInput(windowID: Int64, elementID: String, text: String) {
        let address = InputAddress(windowID: windowID, elementID: elementID)
        pendingInputs[address] = text
        inputSequence &+= 1
        inputOrder[address] = inputSequence
        imageHasChanges = true
        scheduleInputSynchronization()
    }

    func clickControl(windowID: Int64, elementID: String) async {
        let root = states[windowID]?.content
        let button = element(in: root, where: { $0.id == elementID })
        var selection = ""
        if let source = button?.selectionSource, let editor = element(in: root, where: { $0.id == source }) {
            let range = editorSelection(windowID: windowID, elementID: source)
            let text = inputText(windowID: windowID, element: editor) as NSString
            if range.location <= text.length && range.length <= text.length - range.location {
                selection = text.substring(with: range)
            }
        }
        await sendControl(.click(windowID: windowID, elementID: elementID, selection: selection), windowID: windowID, allowInputFailure: states[windowID]?.kind == .workspace || states[windowID]?.kind == .browser)
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
        states[windowID]?.error = evaluation.error
        imageHasChanges = true
    }

    func openTool(_ kind: ToolKind) async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        guard await flushWindowState(allowInputFailure: true) else { return }
        apply(await session.windowAction(.open(kind)))
        imageHasChanges = true
    }

    func showWorkspace() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        guard await flushWindowState(allowInputFailure: true) else { return }
        apply(await session.windowAction(.showWorkspace))
    }

    func reset() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        clearPending()
        _ = await session.reset()
        do { try await startUnsavedChangeLog() } catch { self.error = error.localizedDescription }
        apply(await session.snapshot(), replaceBuffers: true)
        imageURL = nil; imageHasChanges = true
        preferences.removeObject(forKey: Self.lastImageKey)
    }

    func openWorkspace() async {
        guard !isRunning else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, UTType(filenameExtension: "st") ?? .plainText]
        panel.allowsOtherFileTypes = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let source = try String(contentsOf: url, encoding: .utf8)
            await openTool(.workspace)
            if let state = workspaceState {
                apply(await session.windowAction(.text(state.id, source)))
                state.documentURL = url
            }
        } catch { self.error = error.localizedDescription }
    }

    func saveWorkspace() async {
        guard !isRunning, let state = workspaceState else { return }
        isRunning = true
        defer { isRunning = false }
        guard await flushWindowState() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "st") ?? .plainText]
        panel.nameFieldStringValue = state.documentURL?.lastPathComponent ?? "Workspace.st"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try state.text.write(to: url, atomically: true, encoding: .utf8); state.documentURL = url; error = nil }
        catch { self.error = error.localizedDescription }
    }

    func openImage() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        let panel = NSOpenPanel()
        panel.title = "Smalltalk-Image öffnen"
        panel.allowedContentTypes = [Self.imageType]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try await restoreImage(from: url) }
        catch { self.error = "Image konnte nicht geladen werden: \(error.localizedDescription)" }
    }

    func saveImage(asNewFile: Bool = false) async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        let url: URL
        if let imageURL, !asNewFile { url = imageURL }
        else {
            let panel = NSSavePanel()
            panel.title = "Smalltalk-Image speichern"
            panel.allowedContentTypes = [Self.imageType]
            panel.nameFieldStringValue = imageURL?.lastPathComponent ?? "Smalltalk.stimage"
            panel.directoryURL = imageURL?.deletingLastPathComponent()
            guard panel.runModal() == .OK, let chosen = panel.url else { return }
            url = chosen
        }
        guard await flushWindowState() else { return }
        do {
            try await session.saveImage(to: url, workspace: workspaceState?.text ?? "", transcript: "")
            apply(await session.snapshot())
            imageURL = url; preferences.set(url.path, forKey: Self.lastImageKey)
            imageHasChanges = !pendingInputs.isEmpty || !pendingWindowEvents.isEmpty
            result = "Image gespeichert: \(url.lastPathComponent)"; error = nil
        } catch { self.error = "Image konnte nicht gespeichert werden: \(error.localizedDescription)" }
    }

    private func clearPending() {
        synchronization?.cancel(); synchronization = nil
        inputEpoch += 1
        inputDebounce?.cancel(); inputDebounce = nil
        windowEpoch += 1
        pendingWindowEvents.removeAll()
        editorSelections.removeAll()
        pendingInputs.removeAll()
        inputOrder.removeAll()
        liveInputs.removeAll()
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
        let history = changes.reversed().filter { (changeClassFilter == nil || $0.className == changeClassFilter) && (changeMethodFilter == nil || $0.selector == changeMethodFilter) }
        if let baseChange, changeClassFilter == baseChange.className, changeMethodFilter == baseChange.selector { return history + [baseChange] }
        return history
    }
    func showChanges(className: String? = nil, selector: String? = nil) async {
        changeClassFilter = className
        changeMethodFilter = selector
        selectedChange = nil
        baseChange = nil
        if let className, let selector { baseChange = await session.baseVersion(of: selector, in: className) }
        await openTool(.changes)
    }
    func openChanges() async {
        guard !isRunning else { return }
        let panel = NSOpenPanel()
        panel.title = "Changes-Protokoll zur Wiederherstellung öffnen"
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
        apply(image.evaluation, replaceBuffers: true)
        imageURL = url; imageHasChanges = false
        preferences.set(url.path, forKey: Self.lastImageKey)
        result = "Image geladen: \(url.lastPathComponent)"; error = nil
    }
}
