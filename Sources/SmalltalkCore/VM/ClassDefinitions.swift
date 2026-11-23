extension SmalltalkRuntime {
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
        catalogDirty = true
    }

    private enum RetainedReference {
        case value(Value), environment(Environment)
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
        func validate(_ body: Body, context: Context, parameters: [String] = []) throws {
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
        var pending = globals.values.map(RetainedReference.value)
        pending.append(contentsOf: evaluationRoots.map(RetainedReference.value))
        for message in pendingMessages {
            switch message.lookup {
            case .classSuper(let home?):
                if case .classObject(let receiver) = message.receiver { try validateHome(receiver, home: home) }
            case .instanceSuper(let home):
                try validateHome(classOf(message.receiver), home: home)
            default:
                break
            }
        }
        for activation in activations {
            try validate(activation.body, context: activation.context)
            pending.append(.value(activation.context.receiver))
            pending.append(.environment(activation.context.environment))
        }
        var seen: Set<ObjectIdentifier> = []
        while let reference = pending.popLast() {
            switch reference {
            case .value(.object(let object)):
                guard seen.insert(ObjectIdentifier(object)).inserted else { continue }
                pending.append(contentsOf: object.fields.values.map(RetainedReference.value))
            case .value(.array(let array)):
                guard seen.insert(ObjectIdentifier(array)).inserted else { continue }
                pending.append(contentsOf: array.elements.map(RetainedReference.value))
            case .value(.block(let block)):
                guard seen.insert(ObjectIdentifier(block)).inserted else { continue }
                try validate(block.body, context: block.context, parameters: block.parameters)
                pending.append(.value(block.context.receiver))
                pending.append(.environment(block.context.environment))
            case .environment(let environment):
                guard seen.insert(ObjectIdentifier(environment)).inserted else { continue }
                pending.append(contentsOf: environment.values.values.map(RetainedReference.value))
                if let parent = environment.parent { pending.append(.environment(parent)) }
            case .value:
                break
            }
        }
    }
}

private extension Body {
    func reference(to removed: Set<String>, excluding outerNames: Set<String>) -> String? {
        let locals = outerNames.union(temporaries)
        return expressions.lazy.compactMap { $0.reference(to: removed, excluding: locals) }.first
    }
}

private extension Expression {
    func reference(to removed: Set<String>, excluding locals: Set<String>) -> String? {
        func isRemoved(_ name: String) -> Bool { removed.contains(name) && !locals.contains(name) }
        switch kind {
        case .literal:
            return nil
        case .variable(let name):
            return isRemoved(name) ? name : nil
        case .assignment(let name, let value):
            return isRemoved(name) ? name : value.reference(to: removed, excluding: locals)
        case .returnValue(let value):
            return value.reference(to: removed, excluding: locals)
        case .block(let parameters, let body):
            return body.reference(to: removed, excluding: locals.union(parameters))
        case .send(let receiver, _, let arguments):
            return receiver.reference(to: removed, excluding: locals) ??
                arguments.lazy.compactMap { $0.reference(to: removed, excluding: locals) }.first
        case .cascade(let receiver, let messages):
            return receiver.reference(to: removed, excluding: locals) ??
                messages.lazy.flatMap(\.arguments).compactMap { $0.reference(to: removed, excluding: locals) }.first
        }
    }
}
