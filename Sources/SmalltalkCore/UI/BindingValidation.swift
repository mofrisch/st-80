extension SmalltalkRuntime {
    struct BindingState {
        let binding: STObject
        let source: STObject
        let property: String
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
            throw SmalltalkError("Invalid MVC binding. A model, view, aspect, or property is missing.")
        }
        let allowed = ["enabled", "visible"].contains(property) ||
            property == "text" && (isUIClass(view.stClass, named: "UILabel") || isUIClass(view.stClass, named: "UITextField")) ||
            property == "title" && isUIClass(view.stClass, named: "UIButton") ||
            ["spacing", "padding"].contains(property) && isUIClass(view.stClass, named: "UIContainer")
        guard allowed else { throw SmalltalkError("\(property) cannot be bound on this view.") }
        return BindingState(binding: binding, source: source, property: property, active: active)
    }

    func validatedBindings(of view: STObject) throws -> [BindingState] {
        guard let storage = view.fields["mvcBindings"] else { return [] }
        if case .nilValue = storage { return [] }
        guard case .array(let array) = storage, array.elements.count <= 8 else {
            throw SmalltalkError("Invalid view binding list.")
        }
        var properties: Set<String> = []
        return try array.elements.map { value in
            let state = try bindingState(value, owner: view)
            guard properties.insert(state.property).inserted else {
                throw SmalltalkError("A view property is bound more than once.")
            }
            return state
        }
    }

    /// Validate persisted dependency edges without executing Smalltalk methods.
    func validateMVCState(in reachable: [STObject]? = nil) throws {
        guard classes["UIBinding"] != nil else { return }
        for object in reachable ?? objects where isUIClass(object.stClass, named: "UIElement") {
            for state in try validatedBindings(of: object) where state.active {
                guard case .array(let dependents)? = state.source.fields["dependents"],
                      dependents.elements.contains(where: { value in
                          if case .object(let observer) = value { return observer === state.binding }
                          return false
                      }) else { throw SmalltalkError("An active MVC binding is missing from its model's observer list.") }
            }
        }
    }
}
