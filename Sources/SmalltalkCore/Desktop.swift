import Foundation

public enum ToolKind: String, CaseIterable, Sendable {
    case workspace, browser, transcript
}

public struct ToolWindowInfo: Identifiable, Sendable {
    public let id: Int64
    public let kind: ToolKind
    public let title: String
    public let text: String
    public let x: Int64
    public let y: Int64
    public let width: Int64
    public let height: Int64
    public let minimized: Bool

    public init(id: Int64, kind: ToolKind, title: String, text: String, x: Int64, y: Int64, width: Int64, height: Int64, minimized: Bool) {
        self.id = id
        self.kind = kind
        self.title = title
        self.text = text
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.minimized = minimized
    }
}

public enum WindowAction: Sendable {
    case open(ToolKind)
    case close(Int64)
    case activate(Int64)
    case text(Int64, String)
    case frame(Int64, x: Int64, y: Int64, width: Int64, height: Int64)
    case minimize(Int64, Bool)
}

extension SmalltalkSession {
    /// Native events become normal Smalltalk messages on the interpreter thread.
    public func windowAction(_ action: WindowAction) async -> EvaluationResult {
        await worker.submit { $0.performWindowAction(action) }
    }
}

extension SmalltalkRuntime {
    static let systemWindowFields = ["id", "kind", "title", "text", "x", "y", "width", "height", "minimized"]
    static let desktopFields = ["windows", "activeWindow", "nextID"]

    /// Used for a new session and for pre-window-manager images. This deliberately
    /// compiles and allocates without sending ANY Smalltalk messages: an image may
    /// redefine Object>>initialize or Class methods with arbitrary side effects.
    func installDesktopIfNeeded(workspace: String) throws {
        let names = ["Desktop", "SystemWindow", "DesktopManager"]
        if globals["Desktop"] != nil {
            guard let windowClass = classes["SystemWindow"], windowClass.ownFields == Self.systemWindowFields,
                  windowClass.superclass === classes["Object"],
                  let managerClass = classes["DesktopManager"], managerClass.ownFields == Self.desktopFields,
                  managerClass.superclass === classes["Object"],
                  case .object(let manager)? = globals["Desktop"] else {
                throw SmalltalkError("Desktop, SystemWindow oder DesktopManager kollidiert mit der Fensterverwaltung.")
            }
            var actualClass: STClass? = manager.stClass
            while let candidate = actualClass {
                if candidate === managerClass { return }
                actualClass = candidate.superclass
            }
            throw SmalltalkError("Desktop ist weder ein DesktopManager noch eine Instanz einer seiner Unterklassen.")
        }
        guard names.allSatisfy({ globals[$0] == nil && classes[$0] == nil }) else {
            throw SmalltalkError("SystemWindow oder DesktopManager existiert bereits; die Fensterverwaltung kann nicht installiert werden.")
        }
        guard classes.count <= 126, globals.count <= 1_149 else {
            throw SmalltalkError("Für die Fensterverwaltung ist kein Platz in der Klassen- oder Globaltabelle.")
        }
        let windowClass = try subclass(of: classes["Object"]!, name: "SystemWindow", fields: Self.systemWindowFields.joined(separator: " "))
        let managerClass = try subclass(of: classes["Object"]!, name: "DesktopManager", fields: Self.desktopFields.joined(separator: " "))
        for source in Self.windowMethods { try compile(source, in: windowClass) }
        for source in Self.desktopMethods { try compile(source, in: managerClass) }

        func allocate(_ stClass: STClass, fields: [String: Value]) throws -> STObject {
            try checkAllocation()
            let object = STObject(stClass)
            object.fields = fields
            objects.append(object)
            return object
        }
        func window(_ id: Int64, _ kind: ToolKind, _ title: String, _ text: String, _ x: Int64, _ y: Int64, _ width: Int64, _ height: Int64) throws -> STObject {
            try allocate(windowClass, fields: [
                "id": .integer(id), "kind": .symbol(kind.rawValue), "title": .string(title), "text": .string(text),
                "x": .integer(x), "y": .integer(y), "width": .integer(width), "height": .integer(height), "minimized": .boolean(false),
            ])
        }
        let workspaceWindow = try window(1, .workspace, "Workspace", workspace, 100, 200, 720, 600)
        let browser = try window(2, .browser, "System Browser", "", 850, 200, 850, 650)
        let transcript = try window(3, .transcript, "Transcript", "", 100, 40, 720, 200)
        let windows = try array([.object(browser), .object(transcript), .object(workspaceWindow)])
        let manager = try allocate(managerClass, fields: ["windows": windows, "activeWindow": .object(workspaceWindow), "nextID": .integer(4)])
        globals["Desktop"] = .object(manager)
    }

    func performWindowAction(_ action: WindowAction) -> EvaluationResult {
        transcript = ""
        steps = 0
        depth = 0
        do {
            guard case .object(let manager)? = globals["Desktop"] else { throw SmalltalkError("Desktop ist keine Fensterverwaltung.") }
            let desktop = Value.object(manager)
            func window(_ id: Int64) throws -> Value {
                let result = try send(desktop, "windowAt:", [.integer(id)])
                guard case .object = result else { throw SmalltalkError("Fenster \(id) existiert nicht.") }
                return result
            }
            let result: Value
            switch action {
            case .open(let kind):
                let selector: String
                switch kind {
                case .workspace: selector = "openWorkspace"
                case .browser: selector = "openBrowser"
                case .transcript: selector = "openTranscript"
                }
                result = try send(desktop, selector, [])
            case .close(let id): result = try send(desktop, "close:", [window(id)])
            case .activate(let id): result = try send(desktop, "activate:", [window(id)])
            case .text(let id, let text): result = try send(window(id), "text:", [.string(text)])
            case .frame(let id, let x, let y, let width, let height):
                let target = try window(id)
                _ = try send(target, "moveToX:y:", [.integer(Self.coordinate(x)), .integer(Self.coordinate(y))])
                result = try send(target, "resizeWidth:height:", [.integer(Self.windowWidth(width)), .integer(Self.windowHeight(height))])
            case .minimize(let id, let minimized):
                result = try send(desktop, minimized ? "minimize:" : "activate:", [window(id)])
            }
            // Native focus, geometry and editing events must not replace the
            // last Do it/compiler result displayed in a workspace.
            _ = result
            return snapshot()
        } catch { return snapshot(error: error.localizedDescription) }
    }

    /// This projection cannot call user methods: snapshots and image loading must
    /// not execute getters or mutate the language graph. Bounds protect AppKit.
    func projectWindows() -> (windows: [ToolWindowInfo], activeID: Int64?, error: String?) {
        guard let desktop = globals["Desktop"] else { return ([], nil, nil) }
        guard case .object(let manager) = desktop, case .array(let list)? = manager.fields["windows"] else {
            return ([], nil, "Desktop enthält keine gültige Fensterliste.")
        }
        var windows: [ToolWindowInfo] = []
        var ids: Set<Int64> = []
        var warning: String? = list.elements.count > 128 ? "Desktop enthält mehr als 128 Fenster." : nil
        var activeID: Int64?
        let active = manager.fields["activeWindow"]
        for value in list.elements.prefix(128) {
            guard case .object(let object) = value,
                  case .integer(let id)? = object.fields["id"], id > 0, ids.insert(id).inserted,
                  case .symbol(let name)? = object.fields["kind"], let kind = ToolKind(rawValue: name),
                  case .string(let title)? = object.fields["title"], case .string(let text)? = object.fields["text"],
                  case .integer(let x)? = object.fields["x"], case .integer(let y)? = object.fields["y"],
                  case .integer(let width)? = object.fields["width"], case .integer(let height)? = object.fields["height"],
                  case .boolean(let minimized)? = object.fields["minimized"] else {
                warning = "Desktop enthält ein ungültiges Fenster; prüfe dessen Instanzvariablen."
                continue
            }
            windows.append(ToolWindowInfo(id: id, kind: kind, title: String(title.prefix(256)), text: text, x: Self.coordinate(x), y: Self.coordinate(y), width: Self.windowWidth(width), height: Self.windowHeight(height), minimized: minimized))
            if case .object(let selected)? = active, selected === object, !minimized { activeID = id }
        }
        return (windows, activeID, warning)
    }

    private static func coordinate(_ value: Int64) -> Int64 { min(100_000, max(-100_000, value)) }
    private static func windowWidth(_ value: Int64) -> Int64 { min(8_192, max(320, value)) }
    private static func windowHeight(_ value: Int64) -> Int64 { min(8_192, max(160, value)) }

    private static let windowMethods = [
        "initialize id := 0. kind := #workspace. title := 'Workspace'. text := ''. x := 100. y := 200. width := 720. height := 600. minimized := false",
        "id ^ id", "id: anID id := anID",
        "kind ^ kind", "kind: aKind kind := aKind",
        "title ^ title", "title: aTitle title := aTitle",
        "text ^ text", "text: aString text := aString",
        "x ^ x", "y ^ y", "width ^ width", "height ^ height",
        "minimized ^ minimized", "minimized: aBoolean minimized := aBoolean",
        "moveToX: newX y: newY x := newX. y := newY",
        "resizeWidth: newWidth height: newHeight width := newWidth. height := newHeight",
    ]

    private static let desktopMethods = [
        "initialize windows := Array new: 0. activeWindow := nil. nextID := 1",
        "windows ^ windows",
        "activeWindow ^ activeWindow",
        "nextID ^ nextID",
        """
        windowAt: anID
            windows do: [ :each | each id = anID ifTrue: [ ^ each ] ].
            ^ nil
        """,
        """
        windowOfKind: aKind
            windows do: [ :each | each kind = aKind ifTrue: [ ^ each ] ].
            ^ nil
        """,
        """
        append: aWindow
            | replacement |
            replacement := Array new: windows size + 1.
            1 to: windows size do: [ :index | replacement at: index put: (windows at: index) ].
            replacement at: replacement size put: aWindow.
            windows := replacement.
            ^ aWindow
        """,
        """
        createKind: aKind title: aTitle
            | window |
            windows size >= 128 ifTrue: [ ^ nil ].
            window := SystemWindow new.
            window id: nextID.
            nextID := nextID + 1.
            window kind: aKind.
            window title: aTitle.
            aKind = #workspace ifTrue: [ window moveToX: 100 + (windows size * 24) y: 200 + (windows size * 24) ].
            aKind = #browser ifTrue: [ window moveToX: 850 y: 200. window resizeWidth: 850 height: 650 ].
            aKind = #transcript ifTrue: [ window moveToX: 100 y: 40. window resizeWidth: 720 height: 200 ].
            self append: window.
            activeWindow := window.
            ^ window
        """,
        "openWorkspace ^ self createKind: #workspace title: 'Workspace'",
        """
        openBrowser
            | existing |
            existing := self windowOfKind: #browser.
            existing notNil ifTrue: [ ^ self activate: existing ].
            ^ self createKind: #browser title: 'System Browser'
        """,
        """
        openTranscript
            | existing |
            existing := self windowOfKind: #transcript.
            existing notNil ifTrue: [ ^ self activate: existing ].
            ^ self createKind: #transcript title: 'Transcript'
        """,
        """
        activate: aWindow
            windows := windows select: [ :each | (each == aWindow) not ].
            self append: aWindow.
            aWindow minimized: false.
            activeWindow := aWindow.
            ^ aWindow
        """,
        """
        chooseActive
            activeWindow := nil.
            windows do: [ :each | each minimized ifFalse: [ activeWindow := each ] ].
            ^ activeWindow
        """,
        """
        close: aWindow
            windows := windows select: [ :each | (each == aWindow) not ].
            activeWindow == aWindow ifTrue: [ self chooseActive ].
            ^ aWindow
        """,
        """
        minimize: aWindow
            aWindow minimized: true.
            activeWindow == aWindow ifTrue: [ self chooseActive ].
            ^ aWindow
        """,
    ]
}
