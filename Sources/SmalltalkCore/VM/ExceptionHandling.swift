/// Only the display text and the user's decision cross the host boundary.
package struct WarningPrompt: Sendable {
    package let message: String
    package let title: String
    package let continueTitle: String
    package let abortTitle: String
}

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

final class SmalltalkSignal {
    let environment: SmalltalkExceptionHandler?
    init(environment: SmalltalkExceptionHandler?) { self.environment = environment }
}

final class SmalltalkExceptionAction {
    let signal: SmalltalkSignal
    let handler: SmalltalkExceptionHandler
    let exception: Value

    init(signal: SmalltalkSignal, handler: SmalltalkExceptionHandler, exception: Value) {
        self.signal = signal
        self.handler = handler
        self.exception = exception
    }
}

struct ExceptionTransfer: Error {
    enum Kind { case returned, retried, resumed, passed, resignaled, unhandled }
    let kind: Kind
    let target: ObjectIdentifier
    // Like ReturnSignal this value stays on the interpreter thread.
    nonisolated(unsafe) let value: Value?

    init(_ kind: Kind, to target: AnyObject, value: Value? = nil) {
        self.kind = kind
        self.target = ObjectIdentifier(target)
        self.value = value
    }
}

extension SmalltalkRuntime {
    func signalZeroDivide(dividend: Value) throws -> Value {
        let exception = try object(classes["ZeroDivide"]!)
        exception.fields["dividend"] = dividend
        return try signalException(.object(exception))
    }

    func evaluateBlock(_ block: Value, cleanup: Value, always: Bool) throws -> Value {
        let result: Value
        do { result = try invokeBlock(block) }
        catch {
            let returning = (error as? ReturnSignal)?.value ?? (error as? ExceptionTransfer)?.value
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
        let previous = exceptionHandler
        let handler = SmalltalkExceptionHandler(selector: selector, action: action, enclosing: previous)
        exceptionHandler = handler
        defer { exceptionHandler = previous }
        let rootCount = evaluationRoots.count
        evaluationRoots.append(block)
        defer { evaluationRoots.removeSubrange(rootCount...) }
        while true {
            do { return try invokeBlock(evaluationRoots[rootCount]) }
            catch let transfer as ExceptionTransfer where transfer.target == ObjectIdentifier(handler) {
                if transfer.kind == .returned { return transfer.value ?? .nilValue }
                guard transfer.kind == .retried else { throw transfer }
                if let replacement = transfer.value { evaluationRoots[rootCount] = replacement }
            }
        }
    }

    func signalException(_ exception: Value) throws -> Value {
        let signal = SmalltalkSignal(environment: exceptionHandler)
        let previousDefault = exceptionDefaultSignal
        exceptionDefaultSignal = nil
        defer { exceptionDefaultSignal = previousDefault }
        let rootCount = evaluationRoots.count
        evaluationRoots.append(exception)
        defer { evaluationRoots.removeSubrange(rootCount...) }
        while true {
            do {
                return try runExceptionAction(for: evaluationRoots[rootCount], from: signal.environment, signal: signal)
            } catch let transfer as ExceptionTransfer where transfer.target == ObjectIdentifier(signal) {
                switch transfer.kind {
                case .resignaled: evaluationRoots[rootCount] = transfer.value ?? .nilValue
                case .unhandled: throw SmalltalkError(try readableString(transfer.value ?? .nilValue))
                default: throw transfer
                }
            }
        }
    }

    private func matchingHandler(for exception: Value, from start: SmalltalkExceptionHandler?) throws -> SmalltalkExceptionHandler? {
        var candidate = start
        while let handler = candidate {
            if try boolean(send(handler.selector, "handles:", [exception])) { return handler }
            candidate = handler.enclosing
        }
        return nil
    }

    private func runExceptionAction(for exception: Value, from start: SmalltalkExceptionHandler?, signal: SmalltalkSignal) throws -> Value {
        let previousHandler = exceptionHandler
        let previousAction = exceptionAction
        defer { exceptionHandler = previousHandler; exceptionAction = previousAction }
        var candidate = start
        while let handler = try matchingHandler(for: exception, from: candidate) {
            let action = SmalltalkExceptionAction(signal: signal, handler: handler, exception: exception)
            exceptionHandler = handler.enclosing
            exceptionAction = action
            do {
                let result = try invokeBlock(handler.action, [exception])
                throw ExceptionTransfer(.returned, to: handler, value: result)
            } catch let transfer as ExceptionTransfer where transfer.target == ObjectIdentifier(action) {
                if transfer.kind == .resumed { return transfer.value ?? .nilValue }
                guard transfer.kind == .passed else { throw transfer }
                candidate = handler.enclosing
                exceptionAction = previousAction
            }
        }
        exceptionHandler = previousHandler
        exceptionAction = nil
        let previousDefault = exceptionDefaultSignal
        exceptionDefaultSignal = signal
        defer { exceptionDefaultSignal = previousDefault }
        let result = try send(exception, "defaultAction", [])
        return try withRoots([result]) { _ in
            if try boolean(send(exception, "isResumable", [])) { return result }
            throw SmalltalkError(try readableString(send(exception, "description", [])))
        }
    }

    static let exceptionControlSelectors: Set<String> = [
        "isNested", "outer", "pass", "resignalAs:", "resume", "resume:", "retry", "retryUsing:", "return", "return:",
    ]

    func respondsToActiveExceptionControl(_ receiver: Value, selector: String) throws -> Bool {
        guard Self.exceptionControlSelectors.contains(selector), let action = exceptionAction else { return false }
        return try equal(receiver, action.exception, identity: true, dispatch: false)
    }

    func exceptionControlPrimitive(_ receiver: Value, _ selector: String, _ arguments: [Value]) throws -> Value? {
        guard let action = exceptionAction, try equal(receiver, action.exception, identity: true, dispatch: false) else {
            if let base = classes["Exception"], classOf(receiver).inherits(from: base) {
                throw SmalltalkError("There is no active handler for this exception.")
            }
            return nil
        }
        switch selector {
        case "isNested":
            return .boolean(try matchingHandler(for: receiver, from: action.handler.enclosing) != nil)
        case "outer":
            return try runExceptionAction(for: receiver, from: action.handler.enclosing, signal: action.signal)
        case "pass":
            throw ExceptionTransfer(.passed, to: action)
        case "resignalAs:":
            throw ExceptionTransfer(.resignaled, to: action.signal, value: arguments[0])
        case "resume", "resume:":
            guard try boolean(send(receiver, "isResumable", [])) else {
                throw SmalltalkError("This exception cannot be resumed.")
            }
            throw ExceptionTransfer(.resumed, to: action, value: arguments.first)
        case "retry", "retryUsing:":
            if let replacement = arguments.first {
                guard case .block(let block) = replacement, block.parameters.isEmpty else {
                    throw SmalltalkError("Retry requires a block without arguments.")
                }
            }
            throw ExceptionTransfer(.retried, to: action.handler, value: arguments.first)
        default:
            throw ExceptionTransfer(.returned, to: action.handler, value: arguments.first)
        }
    }

    func exceptionPrimitive(_ receiver: Value, _ object: STObject, _ selector: String, _ arguments: [Value]) throws -> Value? {
        switch selector {
        case "_confirmWarning:title:continue:abort:":
            guard let warning = classes["Warning"], object.stClass.inherits(from: warning) else { return nil }
            guard let confirmWarning else { return .nilValue }
            let prompt = try WarningPrompt(message: string(arguments[0]), title: string(arguments[1]),
                                           continueTitle: string(arguments[2]), abortTitle: string(arguments[3]))
            try executionCancellation?.checkStop()
            let proceed = confirmWarning(prompt)
            try executionCancellation?.checkStop()
            return .boolean(proceed)
        case "_signalException", "_failUnhandledException":
            guard let exceptionClass = classes["Exception"], object.stClass.inherits(from: exceptionClass) else { return nil }
            if selector == "_signalException" { return try signalException(receiver) }
            let message = try send(receiver, "description", [])
            if let signal = exceptionDefaultSignal { throw ExceptionTransfer(.unhandled, to: signal, value: message) }
            throw SmalltalkError(try readableString(message))
        default:
            return nil
        }
    }
}
