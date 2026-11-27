import Foundation

enum MessageLookup {
    case normal
    case instanceSuper(STClass)
    case classSuper(STClass?)
}

extension SmalltalkRuntime {
    func superLookup(_ context: Context) throws -> MessageLookup {
        if context.methodSide == .classSide, let home = context.homeClass {
            if home.superclass == nil, let root = home.rootMetaclassSuperclass { return .instanceSuper(root) }
            return .classSuper(home.superclass)
        }
        guard let superclass = context.homeClass?.superclass else { throw SmalltalkError("super is unavailable here.") }
        return .instanceSuper(superclass)
    }

    func lookupMethod(_ selector: String, on receiver: Value, startingAt lookup: MessageLookup = .normal) -> (Method, STClass, MethodSide)? {
        let start: STClass
        switch lookup {
        case .normal:
            start = classOf(receiver)
        case .classSuper(let parent):
            start = parent?.metaclass ?? classes["Class"]!
        case .instanceSuper(let parent):
            start = parent
        }
        guard let (method, owner) = start.lookup(selector) else { return nil }
        if let instanceClass = owner.instanceClass { return (method, instanceClass, .classSide) }
        return (method, owner, .instance)
    }

    func send(_ receiver: Value, _ selector: String, _ arguments: [Value], startingAt lookup: MessageLookup = .normal) throws -> Value {
        try withRoots([receiver] + arguments) { _ in
            try enter()
            defer { depth -= 1 }
            guard arguments.count == CodeValidator.arity(of: selector) else { throw SmalltalkError("Wrong number of arguments for \(selector).") }
            if let (method, owner, side) = lookupMethod(selector, on: receiver, startingAt: lookup) {
                return try invoke(method, owner: owner, receiver: receiver, arguments: arguments, side: side)
            }
            if let result = try primitive(receiver, selector, arguments) { return result }
            return try sendUnrecognized(receiver, selector, arguments, startingAt: lookup)
        }
    }

    // Keep failed-send allocation out of the recursive dispatch stack frame.
    private func sendUnrecognized(_ receiver: Value, _ selector: String, _ arguments: [Value],
                                  startingAt lookup: MessageLookup) throws -> Value {
        guard case .normal = lookup, selector != "doesNotUnderstand:",
              let messageClass = classes["FailedMessage"],
              let (handler, owner, side) = lookupMethod("doesNotUnderstand:", on: receiver) else {
            throw SmalltalkError("\(classOf(receiver).name) does not understand \(selector).")
        }
        return try withRoots { roots in
            let argumentArray = try array(arguments)
            roots.add(argumentArray)
            let message = try object(messageClass)
            message.fields["selector"] = .symbol(selector)
            message.fields["arguments"] = argumentArray
            return try invoke(handler, owner: owner, receiver: receiver, arguments: [.object(message)], side: side)
        }
    }

    func invoke(_ method: Method, owner: STClass, receiver: Value, arguments: [Value], side: MethodSide) throws -> Value {
        try withRoots([receiver] + arguments) { _ in
            guard method.parameters.count == arguments.count else { throw SmalltalkError("Wrong number of arguments for \(method.selector).") }
            let environment = try environment()
            for (name, value) in zip(method.parameters, arguments) { environment.values[name] = value }
            nextHome += 1
            let homeID = nextHome
            activeHomes.insert(homeID)
            defer { activeHomes.remove(homeID) }
            let origin = compilationMode ? nil : DebuggerOrigin(source: method.source, selector: method.selector)
            let context = Context(environment: environment, receiver: receiver, homeClass: owner, homeID: homeID,
                                  isWorkspace: false, methodSide: side, debuggerOrigin: origin)
            do {
                _ = try execute(method.body, context: context, referenceBody: method.referenceBody)
                return receiver
            } catch let signal as ReturnSignal where signal.homeID == homeID { return signal.value }
        }
    }

    func invokeBlock(_ value: Value, _ arguments: [Value] = []) throws -> Value {
        try withRoots([value] + arguments) { _ in
            guard case .block(let block) = value else { throw SmalltalkError("Expected a block [...].") }
            guard block.parameters.count == arguments.count else { throw SmalltalkError("Expected \(block.parameters.count) block arguments, got \(arguments.count).") }
            try enter()
            defer { depth -= 1 }
            let environment = try environment(parent: block.context.environment)
            for (name, value) in zip(block.parameters, arguments) { environment.values[name] = value }
            let lexical = block.context
            let context = Context(environment: environment, receiver: lexical.receiver, homeClass: lexical.homeClass,
                                  homeID: lexical.homeID, isWorkspace: lexical.isWorkspace, methodSide: lexical.methodSide,
                                  initializingPool: lexical.initializingPool,
                                  debuggerOrigin: lexical.debuggerOrigin)
            return try execute(block.body, context: context, referenceBody: block.referenceBody, debuggerKind: .block)
        }
    }
}
