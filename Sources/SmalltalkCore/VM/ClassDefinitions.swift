extension SmalltalkRuntime {
    func subclass(of superclass: STClass?, name: String, fields source: String, classFields: [String] = [],
                  classVariables: [String] = [], pools: [String] = [], indexedStorage: IndexedStorage? = nil,
                  ansi: Bool = false, usesANSIAllocation: Bool = false) throws -> STClass {
        if let superclass { try validateSuperclass(superclass) }
        if ansi {
            guard CodeValidator.validNames([name]) else { throw SmalltalkError("Invalid class name \(name).") }
        } else if name.first?.isUppercase != true || !CodeValidator.validNames([name]) {
            throw SmalltalkError("Class names must begin with an uppercase letter.")
        }
        guard globals[name] == nil else { throw SmalltalkError("\(name) already exists.") }
        guard classes.count < Self.classLimit else { throw SmalltalkError("A session can contain at most \(Self.classLimit) classes.") }
        let fields = source.split(whereSeparator: \.isWhitespace).map(String.init)
        try validateFields(fields, inherited: superclass?.fields ?? [])
        try validateFields(classFields, inherited: superclass?.metaclass.fields ?? [])
        try validateFields(classVariables, inherited: [])
        guard Set(classVariables).isDisjoint(with: fields + classFields) else {
            throw SmalltalkError("Class variables share names with instance variables.")
        }
        guard CodeValidator.validNames(pools), pools.allSatisfy({ sharedPools[$0] != nil }) else {
            throw SmalltalkError("Shared pool names must be unique and identify declared pools.")
        }
        let inherited = superclass?.indexedStorage
        let layout = indexedStorage ?? inherited
        guard inherited == nil || indexedStorage == nil || inherited == indexedStorage,
              layout != .byte || fields.isEmpty && (superclass?.fields.isEmpty ?? true) else {
            throw SmalltalkError("Byte-indexed classes cannot have named fields or inherit object-indexed storage.")
        }
        let stClass = STClass(name, superclass: superclass, fields: fields, classFields: classFields,
                              classVariables: classVariables, sharedPools: pools, indexedStorage: indexedStorage,
                              usesANSIAllocation: usesANSIAllocation)
        if superclass == nil { stClass.rootMetaclassSuperclass = classes["Object"] }
        if recordingChanges {
            try journal.append(kind: .classDefinition, className: name, superclass: superclass?.name,
                               fields: fields, classFields: classFields, source: definitionSource(for: stClass))
        }
        classes[name] = stClass
        catalogDirty = true
        globals[name] = .classObject(stClass)
        return stClass
    }

    func validateSuperclass(_ superclass: STClass) throws {
        guard superclass.instanceClass == nil,
              Self.heapBuiltinNames.contains(superclass.name) || !Self.builtinNames.contains(superclass.name) else {
            throw SmalltalkError("Subclassing primitive classes is not implemented.")
        }
    }

    func validateFields(_ fields: [String], inherited: [String]) throws {
        guard CodeValidator.validNames(fields), Set(fields).isDisjoint(with: inherited),
              fields.count + inherited.count <= Self.namedFieldsLimit else {
            throw SmalltalkError("Instance variable names must be valid and unique, with at most \(Self.namedFieldsLimit) variables.")
        }
    }

    func definitionSource(for target: STClass) -> String {
        let parent = target.superclass?.name ?? "nil"
        if (target.superclass == nil && !Self.builtinNames.contains(target.name))
            || target.ownIndexedStorage != nil || !target.classVariables.isEmpty
            || !target.sharedPools.isEmpty || target.name.first?.isUppercase == false {
            return """
            Class named: '\(target.name)' superclass: '\(parent)'
                indexedInstanceVariables: #'\(target.ownIndexedStorage?.rawValue ?? "none")'
                instanceVariableNames: '\(target.ownFields.joined(separator: " "))'
                classVariableNames: '\(target.classVariables.keys.sorted().joined(separator: " "))'
                sharedPools: '\(target.sharedPools.joined(separator: " "))'
                classInstanceVariableNames: '\(target.metaclass.ownFields.joined(separator: " "))'
            """
        }
        let source = "\(parent) subclass: #\(target.name)\n    instanceVariableNames: '\(target.ownFields.joined(separator: " "))'"
        let classFields = target.metaclass.ownFields
        guard !classFields.isEmpty else { return source }
        return source + "\n    classInstanceVariableNames: '\(classFields.joined(separator: " "))'"
    }

    func acceptDefinition(_ source: String, for target: STClass) throws {
        let body = try compileWorkspace(source)
        if let definition = try SmalltalkInterchange.classDeclaration(in: body) {
            guard definition.name == target.name else { throw SmalltalkError("The definition must name the selected class \(target.name).") }
            guard Set(definition.classVariables) == Set(target.classVariables.keys),
                  definition.pools == target.sharedPools, definition.indexedStorage == target.ownIndexedStorage else {
                throw SmalltalkError("A live class must keep its declared shared variables, pools, and indexed storage.")
            }
            try redefineClass(target, superclass: superclass(named: definition.superclass), fields: definition.fields,
                              classFields: definition.classFields, source: source)
            return
        }
        guard body.temporaries.isEmpty, body.expressions.count == 1,
              case .send(let receiver, let selector, let arguments) = body.expressions[0].kind,
              (selector == "subclass:instanceVariableNames:" && arguments.count == 2)
                || (selector == "subclass:instanceVariableNames:classInstanceVariableNames:" && arguments.count == 3),
              case .variable(let parentName) = receiver.kind,
              case .literal(.symbol(let name)) = arguments[0].kind,
              case .literal(.string(let fields)) = arguments[1].kind else {
            throw SmalltalkError("Enter one class definition using subclass:instanceVariableNames: with optional classInstanceVariableNames:.")
        }
        guard name == target.name else { throw SmalltalkError("The definition must name the selected class \(target.name).") }
        guard let parent = classes[parentName] else { throw SmalltalkError("Superclass \(parentName) does not exist.") }
        var classFields: [String] = []
        if arguments.count == 3 {
            guard case .literal(.string(let names)) = arguments[2].kind else {
                throw SmalltalkError("Enter class instance variable names as a string.")
            }
            classFields = names.split(whereSeparator: \.isWhitespace).map(String.init)
        }
        try redefineClass(target, superclass: parent, fields: fields.split(whereSeparator: \.isWhitespace).map(String.init),
                          classFields: classFields, source: source)
    }

    func redefineClass(_ target: STClass, superclass: STClass?, fields: [String], classFields: [String], source: String? = nil) throws {
        guard !Self.builtinNames.contains(target.name) else { throw SmalltalkError("Built-in class layouts are read-only.") }
        if let superclass { try validateSuperclass(superclass) }
        if target.superclass !== superclass {
            func sharedBindings(in parent: STClass?) -> [String: ObjectIdentifier] {
                var result: [String: ObjectIdentifier] = [:]
                var owner = parent
                while let stClass = owner {
                    for name in stClass.classVariables.keys where result[name] == nil { result[name] = ObjectIdentifier(stClass) }
                    owner = stClass.superclass
                }
                return result
            }
            guard superclass?.indexedStorage == target.superclass?.indexedStorage,
                  sharedBindings(in: superclass) == sharedBindings(in: target.superclass) else {
                throw SmalltalkError("Changing superclass must preserve inherited indexed storage and class variable bindings.")
            }
        }
        var ancestor: STClass? = superclass
        while let current = ancestor {
            guard current !== target else { throw SmalltalkError("A class cannot inherit from itself or one of its subclasses.") }
            ancestor = current.superclass
        }
        guard target.superclass !== superclass || target.ownFields != fields || target.metaclass.ownFields != classFields else { return }
        let hierarchy = Array(classes.values) + classes.values.map(\.metaclass)
        let children = Dictionary(grouping: hierarchy.compactMap { item in
            item.superclass.map { (ObjectIdentifier($0), item) }
        }, by: { $0.0 })
        var layouts: [ObjectIdentifier: [String]] = [:]
        var removedFields: [ObjectIdentifier: Set<String>] = [:]

        func plan(_ current: STClass, own: [String], inherited: [String]) throws {
            try validateFields(own, inherited: inherited)
            let layout = inherited + own
            let owner = current.instanceClass ?? current
            guard Set(own).isDisjoint(with: owner.classVariables.keys),
                  current.indexedStorage != .byte || layout.isEmpty else {
                throw SmalltalkError("The named fields conflict with the class's shared or indexed storage.")
            }
            let removed = Set(current.fields).subtracting(layout)
            for method in current.methods.values {
                if !removed.isEmpty, let field = method.body.reference(to: removed, excluding: Set(method.parameters)) {
                    throw SmalltalkError("\(current.name) » \(method.selector) still uses instance variable \(field).")
                }
            }
            let identity = ObjectIdentifier(current)
            layouts[identity] = layout
            if !removed.isEmpty { removedFields[identity] = removed }
            for (_, child) in children[identity] ?? [] {
                try plan(child, own: child.ownFields, inherited: layout)
            }
        }

        try plan(target, own: fields, inherited: superclass?.fields ?? [])
        try plan(target.metaclass, own: classFields, inherited: superclass?.metaclass.fields ?? [])
        try validateRetainedCode(target: target, superclass: superclass, removedFields: removedFields)
        // The allocation registry also holds unreachable instances. Their old
        // field values must not veto an edit to the reachable object space.
        collectGarbage()
        let updates = try objects.compactMap { object -> (object: STObject, previous: [String: Value], next: [String: Value])? in
            guard let layout = layouts[ObjectIdentifier(object.stClass)] else { return nil }
            let next = Dictionary(uniqueKeysWithValues: layout.map { ($0, object.fields[$0] ?? .nilValue) })
            for (name, value) in object.fields where next[name] == nil && !isNil(value) {
                throw SmalltalkError("Instance variable \(name) still holds a value in a \(object.stClass.name) instance.")
            }
            return (object, object.fields, next)
        }
        let classUpdates = try classes.values.compactMap { current -> (target: STClass, previous: [String: Value], next: [String: Value])? in
            guard let layout = layouts[ObjectIdentifier(current.metaclass)] else { return nil }
            let next = Dictionary(uniqueKeysWithValues: layout.map { ($0, current.classState[$0] ?? .nilValue) })
            for (name, value) in current.classState where next[name] == nil && !isNil(value) {
                throw SmalltalkError("Class instance variable \(name) still holds a value in \(current.name).")
            }
            return (current, current.classState, next)
        }

        let previousSuperclass = target.superclass
        let previousRoot = target.rootMetaclassSuperclass
        let previousFields = target.ownFields
        let previousClassFields = target.metaclass.ownFields
        target.superclass = superclass
        target.rootMetaclassSuperclass = superclass == nil ? classes["Object"] : nil
        target.ownFields = fields
        target.metaclass.ownFields = classFields
        for update in updates { update.object.fields = update.next }
        for update in classUpdates { update.target.classState = update.next }
        do {
            try validateCompilerClasses()
            if let error = projectWindows().error { throw SmalltalkError(error) }
            if recordingChanges {
                try journal.append(kind: .classDefinition, className: target.name, superclass: superclass?.name,
                                   fields: fields, classFields: classFields, source: source ?? definitionSource(for: target))
            }
        } catch {
            target.superclass = previousSuperclass
            target.rootMetaclassSuperclass = previousRoot
            target.ownFields = previousFields
            target.metaclass.ownFields = previousClassFields
            for update in updates { update.object.fields = update.previous }
            for update in classUpdates { update.target.classState = update.previous }
            throw error
        }
        if previousSuperclass !== superclass { reindexMVCBindings() }
        catalogDirty = true
    }

    private func validateRetainedCode(target: STClass, superclass: STClass?, removedFields: [ObjectIdentifier: Set<String>]) throws {
        func validateHome(_ receiver: STClass, home: STClass) throws {
            var ancestor: STClass? = receiver
            while let current = ancestor, current !== home {
                if current === target { ancestor = superclass }
                else if current === target.metaclass { ancestor = superclass?.metaclass ?? classes["Object"] }
                else { ancestor = current.superclass }
            }
            guard ancestor != nil else {
                throw SmalltalkError("A method or block on \(receiver.name) still depends on \(home.name) as a superclass.")
            }
        }
        func validate(_ body: BytecodeBody, context: Context, parameters: [String] = []) throws {
            let owner: STClass
            if context.methodSide == .classSide, case .classObject(let receiver) = context.receiver, let home = context.homeClass {
                try validateHome(receiver, home: home)
                owner = home.metaclass
            } else if case .object(let receiver) = context.receiver {
                owner = receiver.stClass
            } else {
                return
            }
            guard let removed = removedFields[ObjectIdentifier(owner)] else { return }
            var locals = Set(parameters)
            var scope: Environment? = context.environment
            while let current = scope {
                locals.formUnion(current.values.keys)
                scope = current.parent
            }
            if let field = body.reference(to: removed, excluding: locals) {
                throw SmalltalkError("A live method or block on \(owner.name) still uses instance variable \(field).")
            }
        }

        // Walk language roots rather than the arena, which also retains garbage.
        // Active scopes cover local blocks and code that may create a block later.
        var pending = retainedRoots
        func validateSend(_ receiver: Value, lookup: MessageLookup) throws {
            switch lookup {
            case .classSuper(let home?):
                if case .classObject(let target) = receiver { try validateHome(target, home: home) }
            case .instanceSuper(let home):
                try validateHome(classOf(receiver), home: home)
            default:
                break
            }
        }
        for message in pendingMessages { try validateSend(message.receiver, lookup: message.lookup) }
        for case .receiver(let receiver, let lookup) in bytecodeOperands { try validateSend(receiver, lookup: lookup) }
        for activation in activations {
            try validate(activation.body, context: activation.context)
        }
        var seen: Set<ObjectIdentifier> = []
        while let reference = pending.popLast() {
            guard seen.insert(reference.identity).inserted else { continue }
            if case .block(let block) = reference {
                try validate(block.body, context: block.context, parameters: block.parameters)
            }
            reference.trace { pending.append($0) }
        }
    }
}
