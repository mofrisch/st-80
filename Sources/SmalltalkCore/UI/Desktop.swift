import Foundation

public enum ToolKind: String, CaseIterable, Sendable {
    case workspace, browser, transcript, custom, changes
}

public struct WindowRect: Sendable, Equatable, Codable {
    public let x: Int64, y: Int64, width: Int64, height: Int64
    public init(x: Int64, y: Int64, width: Int64, height: Int64) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
}

public struct ScreenInfo: Sendable {
    public let id: String
    public let frame: WindowRect
    public init(id: String, frame: WindowRect) { self.id = id; self.frame = frame }
}

public struct BrowserMethodSelection: Sendable, Hashable {
    public let className: String
    public let selector: String
    public let side: MethodSide
    public let isPrimitive: Bool
    fileprivate let windowIdentity: String
    fileprivate let methodIdentity: UUID?
}

public struct ToolWindowInfo: Identifiable, Sendable {
    public let id: Int64
    public let kind: ToolKind
    public let title: String
    public let text: String
    public let x: Int64, y: Int64, width: Int64, height: Int64
    public let minimized: Bool
    public let content: UIElementInfo?
    public let browserMethod: BrowserMethodSelection?
    public let browserMethodSource: String?
    public let identity: String
    public let minimumWidth: Int64, minimumHeight: Int64, maximumWidth: Int64, maximumHeight: Int64
    public let frameRevision: Int64, stateRevision: Int64
    public var frame: WindowRect { WindowRect(x: x, y: y, width: width, height: height) }

    public init(id: Int64, kind: ToolKind, title: String, text: String, x: Int64, y: Int64, width: Int64, height: Int64, minimized: Bool, content: UIElementInfo? = nil, minimumWidth: Int64 = 1, minimumHeight: Int64 = 1, maximumWidth: Int64 = 8192, maximumHeight: Int64 = 8192, frameRevision: Int64 = 1, stateRevision: Int64 = 1, identity: String = "", browserMethod: BrowserMethodSelection? = nil, browserMethodSource: String? = nil) {
        self.id = id; self.kind = kind; self.title = title; self.text = text
        self.x = x; self.y = y; self.width = width; self.height = height
        self.minimized = minimized; self.content = content
        self.browserMethod = browserMethod
        self.browserMethodSource = browserMethodSource
        self.minimumWidth = minimumWidth; self.minimumHeight = minimumHeight
        self.maximumWidth = maximumWidth; self.maximumHeight = maximumHeight
        self.frameRevision = frameRevision; self.stateRevision = stateRevision
        self.identity = identity
    }
}

/// Idempotent native commands. The backend implements these mechanics, never
/// window policy. Revisions and event acknowledgements reject stale async work.
public enum NativeWindowCommand: Sendable {
    case retain([Int64])
    case present(ToolWindowInfo)
    case order([Int64], active: Int64?, request: Int64)
}

public struct WindowCommandBatch: Sendable {
    public let epoch: String
    public let revision: Int64
    public let acknowledgedEvent: Int64
    public let commands: [NativeWindowCommand]
}

public struct NativeWindowEvent: Sendable {
    public enum Kind: Sendable {
        case closeRequested(Int64), activated(Int64), frame(Int64, WindowRect), minimized(Int64, Bool)
        case frameApplied(Int64, request: Int64, WindowRect)
        case screens([ScreenInfo])
    }
    public let epoch: String
    public let sequence: Int64
    public let kind: Kind
    public let windowIdentity: String?
    public init(epoch: String, sequence: Int64, kind: Kind, windowIdentity: String? = nil) {
        self.epoch = epoch; self.sequence = sequence; self.kind = kind; self.windowIdentity = windowIdentity
    }
}

public enum WindowAction: Sendable {
    case showWorkspace
    case arrangeTools
    case showChanges(className: String?, selector: String?, side: MethodSide)
    case open(ToolKind), close(Int64), activate(Int64), text(Int64, String)
    case frame(Int64, x: Int64, y: Int64, width: Int64, height: Int64)
    case minimize(Int64, Bool)
}

extension SmalltalkSession {
    public func windowAction(_ action: WindowAction) async -> EvaluationResult { await worker.submit { $0.performWindowAction(action) } }
    public func windowEvents(_ events: [NativeWindowEvent]) async -> EvaluationResult { await worker.submit { $0.performWindowEvents(events) } }

    public func browserBytecode(windowID: Int64, method: BrowserMethodSelection) async -> String? {
        await worker.submit { $0.browserBytecode(windowID: windowID, method: method) }
    }
}

extension SmalltalkRuntime {
    static let desktopWindowLimit = 128

    func performWindowAction(_ action: WindowAction) -> EvaluationResult {
        beginEvaluation()
        do {
            guard let desktop = globals["Desktop"] else { throw SmalltalkError("Desktop is missing.") }
            func window(_ id: Int64) throws -> Value {
                let value = try send(desktop, "windowAt:", [.integer(id)])
                guard case .object = value else { throw SmalltalkError("Window \(id) does not exist.") }
                return value
            }
            switch action {
            case .showWorkspace: _ = try send(desktop, "showWorkspace", [])
            case .arrangeTools:
                // An explicit arrange request also works in images predating
                // this policy, without replacing an image's own implementation.
                if lookupMethod("arrangeTools", on: desktop) == nil {
                    guard case .object(let manager) = desktop,
                          let source = try SystemLibrary.shared.get().sources.methods["DesktopManager"]?["arrangeTools"] else {
                        throw SmalltalkError("The tool arrangement method is missing.")
                    }
                    try compile(source, in: manager.stClass)
                }
                _ = try send(desktop, "arrangeTools", [])
            case .open(let kind):
                let selectors: [ToolKind: String] = [.workspace: "openWorkspace", .browser: "openBrowser", .transcript: "openTranscript", .custom: "openWindow", .changes: "openChanges"]
                let selector = selectors[kind]!
                try updateToolDefaults(for: kind, selector: selector, on: desktop)
                let opened = try send(desktop, selector, [])
                if case .nilValue = opened, (desktopWindows?.elements.count ?? 0) >= Self.desktopWindowLimit {
                    throw SmalltalkError("The desktop is limited to \(Self.desktopWindowLimit) windows. Close a window and try again.")
                }
            case .showChanges(let className, let selector, let side):
                _ = try send(desktop, "showChangesFor:selector:side:", [
                    className.map(Value.string) ?? .nilValue,
                    selector.map(Value.string) ?? .nilValue,
                    selector == nil ? .nilValue : .symbol(side.rawValue),
                ])
            case .close(let id): _ = try send(desktop, "requestClose:", [window(id)])
            case .activate(let id): _ = try send(desktop, "activate:", [window(id)])
            case .text(let id, let text): _ = try send(window(id), "text:", [.string(text)])
            case .frame(let id, let x, let y, let width, let height):
                _ = try send(window(id), "observeX:y:width:height:", [.integer(x), .integer(y), .integer(width), .integer(height)])
            case .minimize(let id, let minimized): _ = try send(desktop, minimized ? "minimize:" : "activate:", [window(id)])
            }
            return finishEvaluation()
        } catch { return finishEvaluation(error: error.localizedDescription) }
    }

    /// Update unchanged system methods on first use. Loading itself preserves
    /// the saved desktop, controls, and any authored methods.
    private func updateToolDefaults(for kind: ToolKind, selector: String, on desktop: Value) throws {
        let legacySource: String
        switch kind {
        case .workspace: legacySource = "openWorkspace\n    ^ self createKind: #workspace title: 'Workspace'"
        case .browser:
            legacySource = """
            openBrowser
                | existing | existing := self windowOfKind: #browser.
                existing notNil ifTrue: [ ^ self activate: existing ].
                ^ self createKind: #browser title: 'System Browser'
            """
        case .transcript: legacySource = "openTranscript\n    ^ self createKind: #transcript title: 'Transcript'"
        case .custom, .changes: return
        }
        try updateStockMethod(selector, on: desktop, in: "DesktopManager", replacing: legacySource)
        if kind == .transcript {
            let legacyCreation = """
            createKind: aKind title: aTitle
                | window |
                self windows size >= 128 ifTrue: [ ^ nil ].
                window := self windowClassFor: aKind.
                window := window new.
                window kind: aKind; title: aTitle.
                (aKind = #browser or: [ aKind = #changes ]) ifTrue: [ window moveToX: 850 y: 200; resizeWidth: 850 height: 650 ].
                aKind = #transcript ifTrue: [ window moveToX: 100 y: 40; resizeWidth: 720 height: 200 ].
                self cascadeTool: window.
                ^ self open: window
            """
            try updateStockMethod("createKind:title:", on: desktop, in: "DesktopManager", replacing: legacyCreation)
            guard let buffer = globals["TranscriptBuffer"] else { return }
            let legacyText = """
            text
                contents size = 0 ifTrue: [ ^ 'Transcript show: ''Hello''; cr.' ].
                ^ contents
            """
            if try updateStockMethod("text", on: buffer, in: "TranscriptModel", replacing: legacyText) {
                _ = try send(buffer, "changed:", [.symbol("text")])
            }
        }
    }

    @discardableResult
    private func updateStockMethod(_ selector: String, on receiver: Value, in className: String,
                                   replacing legacySource: String) throws -> Bool {
        guard let (method, owner, _) = lookupMethod(selector, on: receiver), owner === classes[className],
              method.source == legacySource else { return false }
        guard let source = try SystemLibrary.shared.get().sources.methods[className]?[selector] else {
            throw SmalltalkError("The bundled \(className)>>\(selector) method is missing.")
        }
        try compile(source, in: owner)
        return true
    }

    func notifyDesktopOfCatalogChange() throws {
        guard catalogDirty else { return }
        catalogDirty = false
        guard let windows = desktopWindows, windows.elements.count <= Self.desktopWindowLimit,
              case .object(let desktop)? = globals["Desktop"] else { return }
        let receiver = Value.object(desktop)
        let selector = "catalogChanged"
        let library = try? SystemLibrary.shared.get()
        let source = library?.sources.methods["DesktopManager"]?[selector]
        // The bundled hook refreshes each window. Its total budget scales with
        // the bounded desktop size, while an image's own hook has the usual limit.
        let stockLimit = max(Self.executionStepLimit, 50_000 * windows.elements.count)
        if let (method, owner, _) = lookupMethod(selector, on: receiver) {
            let limit = owner === classes["DesktopManager"] && method.source == source ? stockLimit : Self.executionStepLimit
            try withToolExecutionBudget(limit) { _ = try send(receiver, selector, []) }
            return
        }

        // An earlier image can run the bundled hook at the execution boundary
        // without installing methods or changing the saved class dictionary.
        guard isUIClass(desktop.stClass, named: "DesktopManager") else { return }
        guard let code = library?.seed.methods["DesktopManager"]?[selector], let source else {
            throw SmalltalkError("The bundled catalog update is missing.")
        }
        let method = try code.validatedMethod(selector: selector, source: source)
        try withToolExecutionBudget(stockLimit) {
            _ = try invoke(method, owner: desktop.stClass, receiver: receiver, arguments: [], side: .instance)
        }
    }

    func synchronizeChangeHistory() throws {
        guard let windows = desktopWindows, windows.elements.count <= Self.desktopWindowLimit,
              let desktop = globals["Desktop"],
              lookupMethod("synchronizeChanges", on: desktop) != nil else { return }
        try withToolExecutionBudget { _ = try send(desktop, "synchronizeChanges", []) }
    }

    func performWindowEvents(_ events: [NativeWindowEvent]) -> EvaluationResult {
        beginEvaluation()
        var failure: String?
        for event in events where event.epoch == windowEpoch && event.sequence > acknowledgedWindowEvent {
            // A failed user policy must not poison subsequent native facts.
            acknowledgedWindowEvent = event.sequence
            do {
                guard let desktop = globals["Desktop"] else { continue }
                if case .screens(let screens) = event.kind {
                    guard screens.count <= 32 else { throw SmalltalkError("Too many displays.") }
                    try withRoots([desktop]) { roots in
                        var facts: [Value] = []
                        for screen in screens {
                            guard Self.validFrame(screen.frame, screen: true), let stClass = classes["DisplayScreen"] else { throw SmalltalkError("Invalid display geometry.") }
                            let display = try object(stClass)
                            display.fields = ["id": .string(screen.id), "x": .integer(screen.frame.x), "y": .integer(screen.frame.y), "width": .integer(screen.frame.width), "height": .integer(screen.frame.height)]
                            let fact = Value.object(display)
                            roots.add(fact)
                            facts.append(fact)
                        }
                        _ = try send(desktop, "screensChanged:", [array(facts)])
                    }
                    continue
                }
                let id: Int64
                switch event.kind {
                case .activated(let value), .closeRequested(let value), .frame(let value, _), .minimized(let value, _), .frameApplied(let value, _, _): id = value
                case .screens: continue
                }
                let window = try send(desktop, "windowAt:", [.integer(id)])
                guard case .object(let target) = window,
                      event.windowIdentity == nil || event.windowIdentity == target.nativeID else { continue }
                switch event.kind {
                case .closeRequested: _ = try send(desktop, "requestClose:", [window])
                case .activated: _ = try send(desktop, "observeActivation:", [window])
                case .minimized(_, let flag): _ = try send(desktop, "observeMinimized:value:", [window, .boolean(flag)])
                case .frame(_, let rect), .frameApplied(_, _, let rect):
                    guard Self.validFrame(rect) else { throw SmalltalkError("Invalid native window geometry.") }
                    let coordinates: [Value] = [.integer(rect.x), .integer(rect.y), .integer(rect.width), .integer(rect.height)]
                    if case .frameApplied(_, let revision, _) = event.kind { _ = try send(window, "frameApplied:x:y:width:height:", [.integer(revision)] + coordinates) }
                    else { _ = try send(window, "observeX:y:width:height:", coordinates) }
                case .screens: break
                }
            } catch { failure = failure ?? error.localizedDescription }
        }
        return finishEvaluation(error: failure)
    }

    static func validFrame(_ frame: WindowRect, screen: Bool = false) -> Bool {
        (-100_000...100_000).contains(frame.x) && (-100_000...100_000).contains(frame.y) &&
        (1...(screen ? 100_000 : 8192)).contains(frame.width) && (1...(screen ? 100_000 : 8192)).contains(frame.height)
    }

    // Reading the object graph here is deliberate: projections and native
    // control lookup must not execute Smalltalk accessors.
    var desktopModel: STObject? {
        guard case .object(let manager)? = globals["Desktop"],
              case .object(let model)? = manager.fields["model"] else { return nil }
        return model
    }

    var desktopWindows: STArray? {
        guard case .array(let windows)? = desktopModel?.fields["windows"] else { return nil }
        return windows
    }

    func projectedWindow(withID id: Int64) -> STObject? {
        guard let windows = desktopWindows else { return nil }
        for case .object(let window) in windows.elements.prefix(Self.desktopWindowLimit) {
            if case .integer(id)? = window.fields["id"] { return window }
        }
        return nil
    }

    private func selectedBrowserMethod(in window: STObject) -> (selection: BrowserMethodSelection, compiled: Method?)? {
        guard case .symbol("browser")? = window.fields["kind"], isUIClass(window.stClass, named: "BrowserWindow"),
              case .boolean(false)? = window.fields["editingDefinition"],
              case .string(let className)? = window.fields["className"], let target = classes[className],
              case .string(let selector)? = window.fields["selector"],
              case .symbol(let sideName)? = window.fields["methodSide"], let side = MethodSide(rawValue: sideName) else { return nil }
        let compiled = target[side][selector]
        let primitive = isReflectedPrimitive(selector, on: target, side: side)
        guard compiled != nil || primitive else { return nil }
        return (BrowserMethodSelection(className: className, selector: selector, side: side, isPrimitive: primitive,
                                       windowIdentity: window.nativeID, methodIdentity: compiled?.identity), compiled)
    }

    func browserBytecode(windowID: Int64, method: BrowserMethodSelection) -> String? {
        guard let window = projectedWindow(withID: windowID), let selected = selectedBrowserMethod(in: window),
              selected.selection == method, let compiled = selected.compiled else { return nil }
        return compiled.body.disassembly(parameters: compiled.parameters)
    }

    /// Field-only projection. Numerical bounds protect AppKit; policy lives in .st.
    func projectWindows() -> (windows: [ToolWindowInfo], activeID: Int64?, error: String?) {
        if let bootstrapError { return ([], nil, bootstrapError) }
        guard globals["Desktop"] != nil else { return ([], nil, nil) }
        guard let model = desktopModel, let list = desktopWindows else { return ([], nil, "Desktop has no valid window list.") }
        var windows: [ToolWindowInfo] = [], ids: Set<Int64> = []
        var warning: String? = list.elements.count > Self.desktopWindowLimit ? "Desktop has more than \(Self.desktopWindowLimit) windows." : nil
        var activeID: Int64?
        for value in list.elements.prefix(Self.desktopWindowLimit) {
            guard case .object(let object) = value,
                  case .integer(let id)? = object.fields["id"], id > 0, ids.insert(id).inserted,
                  case .symbol(let name)? = object.fields["kind"], let kind = ToolKind(rawValue: name),
                  case .string(let title)? = object.fields["title"], case .string(let text)? = object.fields["text"],
                  case .integer(let x)? = object.fields["x"], case .integer(let y)? = object.fields["y"],
                  case .integer(let width)? = object.fields["width"], case .integer(let height)? = object.fields["height"],
                  case .boolean(let minimized)? = object.fields["minimized"],
                  case .integer(let minW)? = object.fields["nativeMinimumWidth"], case .integer(let minH)? = object.fields["nativeMinimumHeight"],
                  case .integer(let maxW)? = object.fields["nativeMaximumWidth"], case .integer(let maxH)? = object.fields["nativeMaximumHeight"],
                  case .integer(let frameRevision)? = object.fields["frameRevision"], frameRevision > 0,
                  case .integer(let stateRevision)? = object.fields["stateRevision"], stateRevision > 0,
                  Self.validFrame(WindowRect(x: x, y: y, width: width, height: height)),
                  (1...8192).contains(minW), (1...8192).contains(minH), (minW...8192).contains(maxW), (minH...8192).contains(maxH) else {
                warning = "Desktop contains an invalid window. Check its instance variables."; continue
            }
            var content: UIElementInfo?
            if object.fields["content"] != nil || kind == .custom {
                do { content = try projectWindowContent(object) } catch { warning = error.localizedDescription }
            }
            let method = selectedBrowserMethod(in: object)
            windows.append(ToolWindowInfo(id: id, kind: kind, title: String(title.prefix(256)), text: text, x: x, y: y, width: width, height: height,
                                          minimized: minimized, content: content, minimumWidth: minW, minimumHeight: minH, maximumWidth: maxW,
                                          maximumHeight: maxH, frameRevision: frameRevision, stateRevision: stateRevision, identity: object.nativeID,
                                          browserMethod: method?.selection, browserMethodSource: method?.compiled?.source))
            if case .object(let selected)? = model.fields["activeWindow"], selected === object, !minimized { activeID = id }
        }
        return (windows, activeID, warning)
    }

    func projectWindowCommands(_ windows: [ToolWindowInfo], active: Int64?, valid: Bool) -> WindowCommandBatch {
        windowCommandRevision += 1
        var commands: [NativeWindowCommand] = []
        // Invalid projections must not destroy the native editor needed to repair them.
        if valid { commands.append(.retain(windows.map(\.id))) }
        commands += windows.map { .present($0) }
        if case .integer(let request)? = desktopModel?.fields["focusRevision"] {
            commands.append(.order(windows.map(\.id), active: active, request: request))
        }
        return WindowCommandBatch(epoch: windowEpoch, revision: windowCommandRevision, acknowledgedEvent: acknowledgedWindowEvent, commands: commands)
    }
}
