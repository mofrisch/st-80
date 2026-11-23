import Foundation

extension SmalltalkRuntime {
    /// Execution boundaries may reconnect mounted bindings and invoke their
    /// accessors. snapshot(), drawing and image loading remain read-only.
    func finishEvaluation(value: String? = nil, error: String? = nil) -> EvaluationResult {
        var failure = error
        do {
            try refreshToolWindowsIfNeeded()
            try synchronizeMVCBindings()
        } catch {
            failure = failure ?? error.localizedDescription
        }
        let requests = toolRequests
        toolRequests.removeAll()
        return snapshot(value: value, error: failure, requests: requests)
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
        let allowed = ["enabled", "visible"].contains(property) ||
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
        guard case .object(let desktop)? = globals["Desktop"], case .object(let model)? = desktop.fields["model"], case .array(let windows)? = model.fields["windows"] else { return [] }
        var mounted: Set<ObjectIdentifier> = []
        for value in windows.elements.prefix(128) {
            guard case .object(let window) = value,
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
