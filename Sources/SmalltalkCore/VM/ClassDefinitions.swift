extension SmalltalkRuntime {
    func subclass(of superclass: STClass, name: String, fields source: String) throws -> STClass {
        try validateSuperclass(superclass)
        guard name.first?.isUppercase == true && name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else {
            throw SmalltalkError("Class names must begin with an uppercase letter.")
        }
        guard globals[name] == nil else { throw SmalltalkError("\(name) already exists.") }
        guard classes.count < 128 else { throw SmalltalkError("A session can contain at most 128 classes.") }
        let fields = source.split(whereSeparator: \.isWhitespace).map(String.init)
        try validateFields(fields, inherited: superclass.fields)
        if recordingChanges {
            let escaped = source.replacingOccurrences(of: "'", with: "''")
            try journal.append(kind: .classDefinition, className: name, superclass: superclass.name, fields: fields, source: "\(superclass.name) subclass: #\(name) instanceVariableNames: '\(escaped)'")
        }
        let stClass = STClass(name, superclass: superclass, fields: fields)
        classes[name] = stClass
        catalogDirty = true
        globals[name] = .classObject(stClass)
        return stClass
    }

    func validateSuperclass(_ superclass: STClass) throws {
        guard superclass.name == "Object" || !Self.builtinNames.contains(superclass.name) else {
            throw SmalltalkError("Subclassing primitive classes is not implemented.")
        }
    }

    func validateFields(_ fields: [String], inherited: [String]) throws {
        guard CodeValidator.validNames(fields), Set(fields).isDisjoint(with: inherited), fields.count + inherited.count <= 64 else {
            throw SmalltalkError("Instance variable names must be valid and unique, with at most 64 variables.")
        }
    }

    func definitionSource(for target: STClass) -> String {
        let parent = target.superclass?.name ?? "nil"
        return "\(parent) subclass: #\(target.name)\n    instanceVariableNames: '\(target.ownFields.joined(separator: " "))'"
    }

    func acceptDefinition(_ source: String, for target: STClass) throws {
        let body = try compileWorkspace(source)
        guard body.temporaries.isEmpty, body.expressions.count == 1,
              case .send(let receiver, "subclass:instanceVariableNames:", let arguments) = body.expressions[0].kind,
              case .variable(let parentName) = receiver.kind, arguments.count == 2,
              case .literal(.symbol(let name)) = arguments[0].kind,
              case .literal(.string(let fields)) = arguments[1].kind else {
            throw SmalltalkError("Enter one class definition using subclass:instanceVariableNames:.")
        }
        guard name == target.name else { throw SmalltalkError("The definition must name the selected class \(target.name).") }
        guard let parent = classes[parentName] else { throw SmalltalkError("Superclass \(parentName) does not exist.") }
        try redefineClass(target, superclass: parent, fields: fields.split(whereSeparator: \.isWhitespace).map(String.init), source: source)
    }

    func redefineClass(_ target: STClass, superclass: STClass, fields: [String], source: String) throws {
        guard !Self.builtinNames.contains(target.name) else { throw SmalltalkError("Built-in class layouts are read-only.") }
        try validateSuperclass(superclass)
        var ancestor: STClass? = superclass
        while let current = ancestor {
            guard current !== target else { throw SmalltalkError("A class cannot inherit from itself or one of its subclasses.") }
            ancestor = current.superclass
        }
        guard target.superclass !== superclass || target.ownFields != fields else { return }
        let children = Dictionary(grouping: classes.values.compactMap { item in
            item.superclass.map { (ObjectIdentifier($0), item) }
        }, by: { $0.0 })
        var layouts: [ObjectIdentifier: [String]] = [:]
        var removedFields: [ObjectIdentifier: Set<String>] = [:]

        func plan(_ current: STClass, own: [String], inherited: [String]) throws {
            try validateFields(own, inherited: inherited)
            let layout = inherited + own
            let removed = Set(current.fields).subtracting(layout)
            for method in current.methods.values {
                try CodeValidator.check(method, fields: layout)
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

        try plan(target, own: fields, inherited: superclass.fields)
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

        let previousSuperclass = target.superclass
        let previousFields = target.ownFields
        target.superclass = superclass
        target.ownFields = fields
        for update in updates { update.object.fields = update.next }
        do {
            try validateCompilerClasses()
            if let error = projectWindows().error { throw SmalltalkError(error) }
            if recordingChanges {
                try journal.append(kind: .classDefinition, className: target.name, superclass: superclass.name, fields: fields, source: source)
            }
        } catch {
            target.superclass = previousSuperclass
            target.ownFields = previousFields
            for update in updates { update.object.fields = update.previous }
            throw error
        }
        if previousSuperclass !== superclass { reindexMVCBindings() }
        catalogDirty = true
    }

    private func validateRetainedCode(target: STClass, superclass: STClass, removedFields: [ObjectIdentifier: Set<String>]) throws {
        func validateHome(_ receiver: STClass, home: STClass) throws {
            var ancestor: STClass? = receiver
            while let current = ancestor, current !== home {
                ancestor = current === target ? superclass : current.superclass
            }
            guard ancestor != nil else {
                throw SmalltalkError("A method or block on \(receiver.name) still depends on \(home.name) as a superclass.")
            }
        }
        func validate(_ body: BytecodeBody, context: Context, parameters: [String] = []) throws {
            if context.methodSide == .classSide, case .classObject(let receiver) = context.receiver, let home = context.homeClass {
                try validateHome(receiver, home: home)
            }
            guard case .object(let receiver) = context.receiver,
                  let removed = removedFields[ObjectIdentifier(receiver.stClass)] else { return }
            var locals = Set(parameters)
            var scope: Environment? = context.environment
            while let current = scope {
                locals.formUnion(current.values.keys)
                scope = current.parent
            }
            if let field = body.reference(to: removed, excluding: locals) {
                throw SmalltalkError("A live method or block on \(receiver.stClass.name) still uses instance variable \(field).")
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
