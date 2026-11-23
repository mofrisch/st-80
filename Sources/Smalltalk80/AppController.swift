import AppKit
import SmalltalkCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class ToolWindowState {
    let id: Int64
    let kind: ToolKind
    var text: String { didSet { if text != oldValue { changed?() } } }
    var selection = NSRange(location: 0, length: 0)
    var documentURL: URL?
    var result = "Bereit. Auswahl oder gesamten Workspace mit ⌘D ausführen."
    var error: String?
    var content: UIElementInfo?
    @ObservationIgnored var changed: (() -> Void)?

    init(_ info: ToolWindowInfo) {
        id = info.id
        kind = info.kind
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
    var lastWorkspaceID: Int64?
    var selectedClass: String? = "Counter"
    var selectedMethod: String?
    var methodSource = ""
    var methodSelection = NSRange(location: 0, length: 0)
    var classes: [ClassInfo] = []
    var bindings: [BindingInfo] = []
    var transcript = "" { didSet { if transcript != oldValue && !restoring { imageHasChanges = true } } }
    var result = "Bereit."
    var error: String?
    var isRunning = false {
        didSet {
            if !isRunning { scheduleSynchronization(); scheduleInputSynchronization() }
        }
    }
    var search = ""
    var imageURL: URL?
    var imageHasChanges = true
    private let session = SmalltalkSession()
    private let preferences: UserDefaults
    private var hasLoaded = false
    private var restoring = false
    private var dirtyText: Set<Int64> = []
    private struct InputAddress: Hashable {
        let windowID: Int64
        let elementID: String
    }
    private var pendingInputs: [InputAddress: String] = [:]
    private var inputOrder: [InputAddress: UInt64] = [:]
    @ObservationIgnored private var inputSequence: UInt64 = 0
    private var liveInputs: Set<InputAddress> = []
    @ObservationIgnored private var inputDebounce: Task<Void, Never>?
    @ObservationIgnored private var inputFlush: (id: UUID, task: Task<Bool, Never>)?
    @ObservationIgnored private var inputEpoch = 0
    private var pendingFrames: [Int64: NSRect] = [:]
    private var pendingMinimized: [Int64: Bool] = [:]
    private var pendingClose: Set<Int64> = []
    private var pendingActive: Int64?
    private var synchronization: Task<Void, Never>?
    @ObservationIgnored private var nativeWindows: NativeWindowManager?
    private static let lastImageKey = "lastImagePath"
    private static var imageType: UTType { UTType(filenameExtension: "stimage", conformingTo: .data) ?? .data }

    init() {
        let suite = ProcessInfo.processInfo.environment["ST80_PREFERENCES_SUITE"]
        preferences = suite.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    var activeKind: ToolKind? { activeWindowID.flatMap { states[$0]?.kind } }
    var workspaceState: ToolWindowState? {
        if let id = activeWindowID, let state = states[id], state.kind == .workspace { return state }
        return lastWorkspaceID.flatMap { states[$0] }
    }
    var currentClass: ClassInfo? { classes.first { $0.name == selectedClass } }
    var currentMethod: MethodInfo? { currentClass?.methods.first { $0.selector == selectedMethod } }
    var isPrimitive: Bool { currentMethod?.isPrimitive == true }
    var filteredClasses: [ClassInfo] { classes.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) } }

    func load() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        nativeWindows = NativeWindowManager(
            content: { [weak self] id in
                guard let self else { return AnyView(EmptyView()) }
                return AnyView(ToolContentView(controller: self, windowID: id))
            },
            onActivate: { [weak self] id in self?.activated(id) },
            onClose: { [weak self] id in
                self?.pendingClose.insert(id)
                self?.scheduleSynchronization()
            },
            onFrame: { [weak self] id, frame in
                self?.pendingFrames[id] = frame
                self?.imageHasChanges = true
                self?.scheduleSynchronization()
            },
            onMinimize: { [weak self] id, minimized in
                self?.pendingMinimized[id] = minimized
                self?.imageHasChanges = true
                self?.scheduleSynchronization()
            }
        )
        isRunning = true
        defer { isRunning = false }
        if let path = preferences.string(forKey: Self.lastImageKey) {
            do { try await restoreImage(from: URL(fileURLWithPath: path)); return }
            catch { self.error = "Das letzte Image konnte nicht geladen werden: \(error.localizedDescription)" }
        }
        let failure = error
        apply(await session.snapshot(), replaceBuffers: true)
        error = failure
    }

    private func activated(_ id: Int64) {
        guard states[id] != nil, activeWindowID != id else { return }
        activeWindowID = id
        if states[id]?.kind == .workspace { lastWorkspaceID = id }
        pendingActive = id
        imageHasChanges = true
        scheduleSynchronization()
    }

    private func scheduleSynchronization() {
        // Native focus and geometry are flushed before the next interpreter job.
        // Merely clicking into an editor must not briefly disable text input.
        guard hasLoaded, !isRunning, synchronization == nil, !pendingClose.isEmpty else { return }
        synchronization = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard let self else { return }
            self.synchronization = nil
            guard !self.isRunning else { return }
            self.isRunning = true
            await self.flushWindowState(allowInputFailure: true)
            self.isRunning = false
        }
    }

    private func apply(_ evaluation: EvaluationResult, replaceBuffers: Bool = false, appendTranscript: Bool = true) {
        classes = evaluation.classes
        bindings = evaluation.bindings
        error = evaluation.error
        if let value = evaluation.value { result = value }
        if appendTranscript { transcript += evaluation.transcript }
        if transcript.count > 100_000 { transcript = String(transcript.suffix(80_000)) }
        restoring = true
        let ids = Set(evaluation.windows.map(\.id))
        states = states.filter { ids.contains($0.key) }
        dirtyText.formIntersection(ids)
        pendingFrames = pendingFrames.filter { ids.contains($0.key) }
        pendingMinimized = pendingMinimized.filter { ids.contains($0.key) }
        pendingClose.formIntersection(ids)
        if let id = pendingActive, !ids.contains(id) { pendingActive = nil }
        for info in evaluation.windows {
            if let state = states[info.id], state.kind == info.kind, !replaceBuffers {
                if !dirtyText.contains(info.id) { state.text = info.text }
                state.content = info.content
            } else {
                let state = ToolWindowState(info)
                state.changed = { [weak self] in
                    guard let self, !self.restoring else { return }
                    self.dirtyText.insert(info.id)
                    self.imageHasChanges = true
                }
                states[info.id] = state
            }
        }
        var visibleInputs: Set<InputAddress> = []
        var visibleLiveInputs: Set<InputAddress> = []
        func collectInputs(_ node: UIElementInfo, windowID: Int64) {
            if node.kind == .textField {
                let address = InputAddress(windowID: windowID, elementID: node.id)
                visibleInputs.insert(address)
                if node.liveInput { visibleLiveInputs.insert(address) }
            }
            for child in node.children { collectInputs(child, windowID: windowID) }
        }
        for info in evaluation.windows {
            if let content = info.content { collectInputs(content, windowID: info.id) }
        }
        pendingInputs = pendingInputs.filter { visibleInputs.contains($0.key) }
        inputOrder = inputOrder.filter { visibleInputs.contains($0.key) }
        liveInputs = visibleLiveInputs
        restoring = false
        windowInfos = evaluation.windows
        if pendingActive == nil { activeWindowID = evaluation.activeWindowID }
        if let id = activeWindowID, states[id]?.kind == .workspace { lastWorkspaceID = id }
        if lastWorkspaceID.flatMap({ states[$0] }) == nil {
            lastWorkspaceID = evaluation.windows.first { $0.kind == .workspace }?.id
        }
        // Native events may arrive while an interpreter job is running. Project
        // those newer events over its snapshot without delaying newly opened tools.
        var visibleWindows = evaluation.windows.map { info in
            let frame = pendingFrames[info.id]
            return ToolWindowInfo(
                id: info.id, kind: info.kind, title: info.title, text: info.text,
                x: frame.map { Int64($0.origin.x.rounded()) } ?? info.x,
                y: frame.map { Int64($0.origin.y.rounded()) } ?? info.y,
                width: frame.map { Int64($0.width.rounded()) } ?? info.width,
                height: frame.map { Int64($0.height.rounded()) } ?? info.height,
                minimized: pendingMinimized[info.id] ?? info.minimized, content: info.content
            )
        }
        if let id = pendingActive, let index = visibleWindows.firstIndex(where: { $0.id == id }) {
            let front = visibleWindows.remove(at: index)
            visibleWindows.append(front)
        }
        nativeWindows?.synchronize(visibleWindows, activeID: pendingActive ?? evaluation.activeWindowID)
    }

    private func captureGeometry() {
        for (id, frame) in nativeWindows?.captureFrames() ?? [:] {
            guard let saved = windowInfos.first(where: { $0.id == id }) else { continue }
            if saved.x != Int64(frame.origin.x.rounded()) || saved.y != Int64(frame.origin.y.rounded()) ||
                saved.width != Int64(frame.width.rounded()) || saved.height != Int64(frame.height.rounded()) {
                pendingFrames[id] = frame
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
        var inputOutput = ""
        var acknowledged: [(InputAddress, String)] = []
        func acknowledgeInputs() {
            for (address, text) in acknowledged where pendingInputs[address] == text {
                pendingInputs.removeValue(forKey: address)
                inputOrder.removeValue(forKey: address)
            }
        }
        for (address, text) in pendingInputs.sorted(by: { (inputOrder[$0.key] ?? 0) < (inputOrder[$1.key] ?? 0) }) {
            let evaluation = await session.uiAction(.text(windowID: address.windowID, elementID: address.elementID, value: text))
            guard inputEpoch == epoch else { return true }
            inputOutput += evaluation.transcript
            if evaluation.executionError != nil {
                acknowledgeInputs()
                apply(evaluation, appendTranscript: false)
                states[address.windowID]?.error = evaluation.error
                transcript += inputOutput
                return false
            }
            states[address.windowID]?.error = nil
            acknowledged.append((address, text))
            latestInput = evaluation
        }
        acknowledgeInputs()
        if let latestInput { apply(latestInput, appendTranscript: false) }
        transcript += inputOutput
        return true
    }

    /// Flush local edits before evaluating Smalltalk or taking an image snapshot.
    @discardableResult
    private func flushWindowState(allowInputFailure: Bool = false) async -> Bool {
        captureGeometry()
        let inputsValid = await synchronizeInputs()
        guard inputsValid || allowInputFailure else { return false }
        var actions: [WindowAction] = []
        for id in dirtyText.sorted() {
            if let state = states[id] { actions.append(.text(id, state.text)) }
        }
        dirtyText.removeAll()
        for (id, frame) in pendingFrames.sorted(by: { $0.key < $1.key }) {
            actions.append(.frame(id, x: Int64(frame.origin.x.rounded()), y: Int64(frame.origin.y.rounded()), width: Int64(frame.width.rounded()), height: Int64(frame.height.rounded())))
        }
        pendingFrames.removeAll()
        for (id, minimized) in pendingMinimized { actions.append(.minimize(id, minimized)) }
        pendingMinimized.removeAll()
        if let id = pendingActive { actions.append(.activate(id)) }
        pendingActive = nil
        for id in pendingClose.sorted() { actions.append(.close(id)) }
        pendingClose.removeAll()
        var latest: EvaluationResult?
        var output = ""
        for action in actions {
            let evaluation = await session.windowAction(action)
            output += evaluation.transcript
            if evaluation.executionError != nil {
                // Keep editable text if a Smalltalk setter was changed to reject it.
                for (id, state) in states where windowInfos.first(where: { $0.id == id })?.text != state.text { dirtyText.insert(id) }
                apply(evaluation, appendTranscript: false)
                transcript += output
                return false
            }
            latest = evaluation
        }
        if let latest {
            apply(latest, appendTranscript: false)
        }
        transcript += output
        return true
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
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        guard await flushWindowState() else { return }
        let evaluation = await session.uiAction(.click(windowID: windowID, elementID: elementID))
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
        guard let id = workspaceState?.id else { await openTool(.workspace); return }
        isRunning = true
        defer { isRunning = false }
        guard await flushWindowState(allowInputFailure: true) else { return }
        apply(await session.windowAction(.activate(id)))
    }

    func run(windowID: Int64? = nil, printResult: Bool = false) async {
        guard !isRunning, let state = windowID.flatMap({ states[$0] }) ?? workspaceState, state.kind == .workspace else { return }
        isRunning = true
        defer { isRunning = false }
        let text = state.text as NSString
        let selection = state.selection
        let source = selection.length > 0 && NSMaxRange(selection) <= text.length ? text.substring(with: selection) : state.text
        // A broken model/controller method must remain repairable from code,
        // while its pending field value stays available for a subsequent retry.
        guard await flushWindowState(allowInputFailure: true) else { return }
        let evaluation = await session.evaluate(source)
        apply(evaluation)
        state.result = evaluation.value ?? ""
        state.error = evaluation.error
        imageHasChanges = true
        if printResult, let value = evaluation.value { transcript += "→ \(value)\n" }
    }

    func acceptMethod() async {
        guard !isRunning, let selectedClass, !isPrimitive else { return }
        isRunning = true
        defer { isRunning = false }
        guard await flushWindowState(allowInputFailure: true) else { return }
        let evaluation = await session.compile(methodSource, in: selectedClass)
        apply(evaluation)
        if evaluation.error == nil {
            imageHasChanges = true
            selectedMethod = currentClass?.methods.first { $0.source == methodSource }?.selector
        }
    }

    func chooseClass() {
        selectedMethod = nil
        methodSource = ""
        methodSelection = NSRange(location: 0, length: 0)
    }
    func chooseMethod() { methodSource = currentMethod?.source ?? ""; methodSelection = NSRange(location: 0, length: 0) }
    func newMethod() { selectedMethod = nil; methodSource = "newMethod\n    ^ self"; methodSelection = NSRange(location: 0, length: 0) }

    func createClass(name: String, fields: String) async -> Bool {
        guard !isRunning else { return false }
        isRunning = true
        defer { isRunning = false }
        guard await flushWindowState() else { return false }
        let nameLiteral = name.replacingOccurrences(of: "'", with: "''")
        let fieldsLiteral = fields.replacingOccurrences(of: "'", with: "''")
        let evaluation = await session.evaluate("Object subclass: #'\(nameLiteral)' instanceVariableNames: '\(fieldsLiteral)'")
        apply(evaluation)
        if evaluation.error == nil { imageHasChanges = true; selectedClass = name; newMethod(); return true }
        return false
    }

    func reset() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        clearPending()
        apply(await session.reset(), replaceBuffers: true)
        selectedClass = "Counter"; selectedMethod = nil; methodSource = ""
        transcript = ""; imageURL = nil; imageHasChanges = true
        preferences.removeObject(forKey: Self.lastImageKey)
    }

    func example(_ text: String) async {
        await openTool(.workspace)
        workspaceState?.text = text
        workspaceState?.selection = NSRange(location: 0, length: 0)
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
            await example(source)
            workspaceState?.documentURL = url
        } catch { self.error = error.localizedDescription }
    }

    func saveWorkspace() {
        guard !isRunning, let state = workspaceState else { return }
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
            try await session.saveImage(to: url, workspace: workspaceState?.text ?? "", transcript: transcript)
            imageURL = url; preferences.set(url.path, forKey: Self.lastImageKey)
            imageHasChanges = !dirtyText.isEmpty || !pendingInputs.isEmpty || !pendingFrames.isEmpty || !pendingMinimized.isEmpty || !pendingClose.isEmpty || pendingActive != nil
            result = "Image gespeichert: \(url.lastPathComponent)"; error = nil
        } catch { self.error = "Image konnte nicht gespeichert werden: \(error.localizedDescription)" }
    }

    private func clearPending() {
        synchronization?.cancel(); synchronization = nil
        inputEpoch += 1
        inputDebounce?.cancel(); inputDebounce = nil
        dirtyText.removeAll(); pendingFrames.removeAll(); pendingMinimized.removeAll(); pendingClose.removeAll(); pendingActive = nil
        pendingInputs.removeAll()
        inputOrder.removeAll()
        liveInputs.removeAll()
    }

    private func restoreImage(from url: URL) async throws {
        let image = try await session.loadImage(from: url)
        clearPending()
        apply(image.evaluation, replaceBuffers: true)
        transcript = image.transcript
        selectedMethod = nil; methodSource = ""; methodSelection = NSRange(location: 0, length: 0)
        search = ""; imageURL = url; imageHasChanges = false
        preferences.set(url.path, forKey: Self.lastImageKey)
        result = "Image geladen: \(url.lastPathComponent)"; error = nil
    }
}
