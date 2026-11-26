/// The dynamic handler environment. The send of on:do: keeps both operands
/// rooted for the lifetime of the handler, including while it is suspended.
final class SmalltalkExceptionHandler {
    let selector: Value
    let action: Value
    let enclosing: SmalltalkExceptionHandler?

    init(selector: Value, action: Value, enclosing: SmalltalkExceptionHandler?) {
        self.selector = selector
        self.action = action
        self.enclosing = enclosing
    }
}

/// Unwinds to the particular on:do: that handled a signal.
struct ExceptionHandlerReturn: Error {
    let handler: ObjectIdentifier
    // Like ReturnSignal, this value stays on the interpreter thread.
    nonisolated(unsafe) let value: Value
}

extension SmalltalkRuntime {
    func evaluateBlock(_ block: Value, cleanup: Value, always: Bool) throws -> Value {
        let result: Value
        do { result = try invokeBlock(block) }
        catch {
            let returning = (error as? ReturnSignal)?.value ?? (error as? ExceptionHandlerReturn)?.value
            try withRoots(returning.map { [$0] } ?? []) { _ in _ = try invokeBlock(cleanup) }
            throw error
        }
        if always { try withRoots([result]) { _ in _ = try invokeBlock(cleanup) } }
        return result
    }

    /// Older images lack these methods. Preserve any authored Object>>error:.
    func installExceptionProtocol() throws {
        let library = try SystemLibrary.shared.get()
        guard let exception = classes["Exception"], let object = classes["Object"] else {
            throw SmalltalkError("The exception classes are missing.")
        }
        for side in MethodSide.allCases {
            for (selector, code) in library.seed[side]["Exception"] ?? [:] {
                guard let source = library.sources[side]["Exception"]?[selector] else {
                    throw SmalltalkError("The bundled exception method \(selector) is missing.")
                }
                exception[side][selector] = try code.validatedMethod(selector: selector, source: source)
            }
        }
        if object.methods["error:"] == nil {
            guard let code = library.seed.methods["Object"]?["error:"], let source = library.sources.methods["Object"]?["error:"] else {
                throw SmalltalkError("The bundled Object>>error: method is missing.")
            }
            object.methods["error:"] = try code.validatedMethod(selector: "error:", source: source)
        }
    }

    func evaluateProtectedBlock(_ block: Value, selector: Value, action: Value) throws -> Value {
        guard case .block(let handlerBlock) = action, handlerBlock.parameters.count == 1 else {
            throw SmalltalkError("An exception handler must be a one-argument block.")
        }
        guard lookupMethod("handles:", on: selector) != nil else {
            throw SmalltalkError("An exception selector must understand handles:.")
        }
        let previous = exceptionHandler
        let handler = SmalltalkExceptionHandler(selector: selector, action: action, enclosing: previous)
        exceptionHandler = handler
        defer { exceptionHandler = previous }
        do { return try invokeBlock(block) }
        catch let transfer as ExceptionHandlerReturn where transfer.handler == ObjectIdentifier(handler) {
            return transfer.value
        }
    }

    func signalException(_ exception: Value) throws -> Value {
        let signalingEnvironment = exceptionHandler
        defer { exceptionHandler = signalingEnvironment }
        var candidate = signalingEnvironment
        while let handler = candidate {
            if try boolean(send(handler.selector, "handles:", [exception])) {
                exceptionHandler = handler.enclosing
                let result = try invokeBlock(handler.action, [exception])
                throw ExceptionHandlerReturn(handler: ObjectIdentifier(handler), value: result)
            }
            candidate = handler.enclosing
        }
        let result = try send(exception, "defaultAction", [])
        return try withRoots([result]) { _ in
            if try boolean(send(exception, "isResumable", [])) { return result }
            throw SmalltalkError(try string(send(exception, "description", [])))
        }
    }

    func exceptionPrimitive(_ receiver: Value, _ object: STObject, _ selector: String) throws -> Value? {
        switch selector {
        case "_signalException", "_failUnhandledException":
            guard let exceptionClass = classes["Exception"], object.stClass.inherits(from: exceptionClass) else { return nil }
            if selector == "_signalException" { return try signalException(receiver) }
            throw SmalltalkError(try string(send(receiver, "description", [])))
        default:
            return nil
        }
    }
}
