import Foundation

extension SmalltalkRuntime {
    private static let mvcClasses: [UIClassDefinition] = [
        .init(name: "Model", superclass: "Object", fields: ["dependents"], methods: [
            "initialize dependents := nil",
            "dependents dependents isNil ifTrue: [ dependents := Array new: 0 ]. ^ dependents",
            """
            addDependent: anObserver
                | replacement |
                self dependents do: [ :each | each == anObserver ifTrue: [ ^ anObserver ] ].
                replacement := Array new: dependents size + 1.
                1 to: dependents size do: [ :index | replacement at: index put: (dependents at: index) ].
                replacement at: replacement size put: anObserver.
                dependents := replacement.
                ^ anObserver
            """,
            "removeDependent: anObserver dependents := self dependents select: [ :each | (each == anObserver) not ]",
            "changed ^ self changed: nil",
            "changed: anAspect self dependents do: [ :each | each update: anAspect ]",
        ]),
        .init(name: "Controller", superclass: "Object", fields: ["model"], methods: [
            "initialize model := nil", "model ^ model", "model: aModel model := aModel",
        ]),
        .init(name: "UIBinding", superclass: "Object", fields: ["source", "aspect", "view", "property", "active"], methods: [
            "initialize active := false",
            "source: aModel aspect: anAspect view: aView property: aProperty source := aModel. aspect := anAspect. view := aView. property := aProperty",
            "source ^ source", "aspect ^ aspect", "view ^ view", "property ^ property", "active ^ active",
            "connect active ifTrue: [ ^ self ]. active := true. source addDependent: self. self update: nil",
            "disconnect active ifFalse: [ ^ self ]. active := false. source removeDependent: self",
            """
            update: anAspect
                active ifFalse: [ ^ self ].
                (anAspect isNil or: [ anAspect = aspect ]) ifTrue: [
                    view perform: (property asString, ':') asSymbol with: (source perform: aspect) ]
            """,
        ]),
    ]

    func installMVCIfNeeded() throws {
        if classes["Model"] == nil {
            guard Self.mvcClasses.allSatisfy({ classes[$0.name] == nil && globals[$0.name] == nil }),
                  classes.count + Self.mvcClasses.count <= 128 else {
                throw SmalltalkError("Die MVC-Klassen können nicht installiert werden: Namenskonflikt oder Klassentabelle voll.")
            }
            for definition in Self.mvcClasses {
                let stClass = try subclass(of: classes[definition.superclass]!, name: definition.name, fields: definition.fields.joined(separator: " "))
                for method in definition.methods { try compile(method, in: stClass) }
            }
        } else {
            for definition in Self.mvcClasses {
                guard let stClass = classes[definition.name], stClass.ownFields == definition.fields,
                      stClass.superclass === classes[definition.superclass] else {
                    throw SmalltalkError("\(definition.name) kollidiert mit den MVC-Klassen.")
                }
            }
        }
        // Add the protocol to old images without replacing user methods. Lazy
        // binding storage also supports an existing, customized initialize.
        let additions: [(String, String)] = [
            ("UIElement", "bindings mvcBindings isNil ifTrue: [ mvcBindings := Array new: 0 ]. ^ mvcBindings"),
            ("UIElement", """
            bind: aProperty to: aModel aspect: anAspect
                | binding replacement |
                self unbind: aProperty.
                binding := UIBinding new.
                binding source: aModel aspect: anAspect view: self property: aProperty.
                replacement := Array new: self bindings size + 1.
                1 to: mvcBindings size do: [ :index | replacement at: index put: (mvcBindings at: index) ].
                replacement at: replacement size put: binding.
                mvcBindings := replacement.
                binding connect
            """),
            ("UIElement", """
            unbind: aProperty
                self bindings do: [ :each | each property = aProperty ifTrue: [ each disconnect ] ].
                mvcBindings := mvcBindings select: [ :each | (each property = aProperty) not ]
            """),
            ("UIElement", "unbindAll self bindings do: [ :each | each disconnect ]. mvcBindings := nil"),
            ("UIButton", "onClickSend: aSelector to: aController self action: [ aController perform: aSelector ]"),
            ("UITextField", "onChangeSend: aSelector to: aController mvcInputTarget := aController. mvcInputSelector := aSelector"),
            ("UITextField", """
            editText: aString
                self text: aString.
                mvcInputTarget notNil ifTrue: [ ^ mvcInputTarget perform: mvcInputSelector with: aString ]
            """),
        ]
        for (name, source) in additions {
            var parser = try Parser(source)
            let selector = try parser.method(source: source).selector
            if classes[name]!.lookup(selector) == nil { try compile(source, in: classes[name]!) }
        }
    }

    /// Execution boundaries may reconnect mounted bindings and invoke their
    /// accessors. snapshot(), drawing and image loading remain read-only.
    func finishEvaluation(value: String? = nil, error: String? = nil) -> EvaluationResult {
        do {
            try synchronizeMVCBindings()
            return snapshot(value: value, error: error)
        } catch let failure {
            return snapshot(value: value, error: error ?? failure.localizedDescription)
        }
    }

    private struct BindingState {
        let binding: STObject
        let source: STObject
        let view: STObject
        let active: Bool
    }

    private func bindingState(_ value: Value, owner: STObject) throws -> BindingState {
        guard case .object(let binding) = value, isUIClass(binding.stClass, named: "UIBinding"),
              case .object(let source)? = binding.fields["source"], isUIClass(source.stClass, named: "Model"),
              case .object(let view)? = binding.fields["view"], view === owner,
              case .symbol(let aspect)? = binding.fields["aspect"],
              aspect.first.map({ $0.isLetter || $0 == "_" }) == true,
              aspect.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }),
              case .symbol(let property)? = binding.fields["property"],
              case .boolean(let active)? = binding.fields["active"] else {
            throw SmalltalkError("Ungültige MVC-Bindung: Model, View, Aspekt oder Eigenschaft fehlt.")
        }
        let allowed = property == "enabled" ||
            property == "text" && (isUIClass(view.stClass, named: "UILabel") || isUIClass(view.stClass, named: "UITextField")) ||
            property == "title" && isUIClass(view.stClass, named: "UIButton") ||
            ["spacing", "padding"].contains(property) && isUIClass(view.stClass, named: "UIContainer")
        guard allowed else { throw SmalltalkError("\(property) ist keine bindbare Eigenschaft dieser View.") }
        return BindingState(binding: binding, source: source, view: view, active: active)
    }

    private func bindings(of view: STObject) throws -> [BindingState] {
        guard let storage = view.fields["mvcBindings"] else { return [] }
        if case .nilValue = storage { return [] }
        guard case .array(let array) = storage, array.elements.count <= 8 else {
            throw SmalltalkError("Ungültige Bindungsliste einer View.")
        }
        var properties: Set<String> = []
        return try array.elements.map { value in
            let state = try bindingState(value, owner: view)
            guard case .symbol(let property)? = state.binding.fields["property"], properties.insert(property).inserted else {
                throw SmalltalkError("Eine View-Eigenschaft ist mehrfach gebunden.")
            }
            return state
        }
    }

    private func mountedBindingIDs() throws -> Set<ObjectIdentifier> {
        guard case .object(let desktop)? = globals["Desktop"], case .array(let windows)? = desktop.fields["windows"] else { return [] }
        var mounted: Set<ObjectIdentifier> = []
        for value in windows.elements.prefix(128) {
            guard case .object(let window) = value, case .symbol("custom")? = window.fields["kind"],
                  let root = window.fields["content"] else { continue }
            var pending = [root]
            var seen: Set<ObjectIdentifier> = []
            while let value = pending.popLast(), seen.count < 512 {
                guard case .object(let view) = value, isUIClass(view.stClass, named: "UIElement"),
                      seen.insert(ObjectIdentifier(view)).inserted else { continue }
                for state in try bindings(of: view) { mounted.insert(ObjectIdentifier(state.binding)) }
                if isUIClass(view.stClass, named: "UIContainer"), case .array(let children)? = view.fields["children"] {
                    pending.append(contentsOf: children.elements.prefix(512))
                }
            }
        }
        return mounted
    }

    private func synchronizeMVCBindings() throws {
        guard classes["UIBinding"] != nil else { return }
        let mounted = try mountedBindingIDs()
        // Copy the list: user-defined connect/disconnect methods may allocate.
        let bindings = objects.filter { isUIClass($0.stClass, named: "UIBinding") }
        for binding in bindings {
            guard case .boolean(let active)? = binding.fields["active"] else { continue }
            let desired = mounted.contains(ObjectIdentifier(binding))
            if active != desired { _ = try send(.object(binding), desired ? "connect" : "disconnect", []) }
        }
    }

    /// Validate persisted dependency edges without executing Smalltalk methods.
    func validateMVCState(in reachable: [STObject]? = nil) throws {
        guard classes["UIBinding"] != nil else { return }
        for object in reachable ?? objects where isUIClass(object.stClass, named: "UIElement") {
            for state in try bindings(of: object) where state.active {
                guard case .array(let dependents)? = state.source.fields["dependents"],
                      dependents.elements.contains(where: { value in
                          if case .object(let observer) = value { return observer === state.binding }
                          return false
                      }) else { throw SmalltalkError("Eine aktive MVC-Bindung fehlt in der Beobachterliste ihres Models.") }
            }
        }
    }
}

extension ImageCodec {
    /// Add framework slots to images from before MVC. No initialize or accessor
    /// runs, including for user subclasses; their own methods are preserved.
    static func upgradeMVCLayouts(_ image: inout ImageArchive) throws {
        let changes: [(String, [String], [String])] = [
            ("UIElement", ["enabled"], ["mvcBindings"]),
            ("UITextField", ["label", "text", "placeholder"], ["mvcInputTarget", "mvcInputSelector"]),
        ]
        for (name, original, additions) in changes {
            guard let index = image.classes.firstIndex(where: { $0.name == name }), image.classes[index].fields == original else { continue }
            image.classes[index].fields += additions
            let parents = Dictionary(image.classes.map { ($0.name, $0.superclass) }, uniquingKeysWith: { first, _ in first })
            for nodeID in image.nodes.indices {
                guard case .object(var object) = image.nodes[nodeID] else { continue }
                var current: String? = object.className
                var seen: Set<String> = []
                var inherits = false
                while let candidate = current, seen.insert(candidate).inserted {
                    if candidate == name { inherits = true; break }
                    current = parents[candidate] ?? nil
                }
                guard inherits else { continue }
                for field in additions {
                    guard object.fields[field] == nil else { throw SmalltalkError("Ein altes Image verwendet bereits die neue Framework-Variable \(field).") }
                    object.fields[field] = .nilValue
                }
                image.nodes[nodeID] = .object(object)
            }
        }
    }
}
