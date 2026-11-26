import Foundation

/// The compiler runs ordinary Smalltalk methods on the interpreter. Its temporary
/// object memory is released after each translation, including failed ones.
extension SmalltalkRuntime {
    static let compilerClassNames = ["STCompilerList", "STScanner", "STCompiler"]

    func compileWorkspace(_ source: String) throws -> Body {
        let body: Body = try withCompiler(source, selector: "workspace:", decode: CompilerOutput.body)
        try CodeValidator.check(body)
        return body
    }

    func compileMethod(_ source: String) throws -> Method {
        let method = try withCompiler(source, selector: "method:") { output in
            let parts = try CompilerOutput.parts(output, count: 3)
            let body = try CompilerOutput.body(parts[2])
            let parameters = try CompilerOutput.names(parts[1])
            try CodeValidator.check(body, parameters: parameters)
            return Method(
                selector: try CompilerOutput.string(parts[0]),
                parameters: parameters,
                body: BytecodeBody.lower(body),
                source: source,
                referenceBody: useASTInterpreterForTesting ? body : nil
            )
        }
        try CodeValidator.check(method)
        return method
    }

    @discardableResult
    func compile(_ source: String, in stClass: STClass, side: MethodSide = .instance,
                 validating validate: ((Method) throws -> Void)? = nil) throws -> String {
        guard !compilationMode else { throw SmalltalkError("Compilation is already in progress.") }
        let method = try compileMethod(source)
        try validate?(method)
        guard stClass[side].count < Self.methodsPerSideLimit || stClass[side][method.selector] != nil else {
            throw SmalltalkError("Too many methods in \(side.displayName(for: stClass.name)).")
        }
        if recordingChanges {
            try journal.append(kind: .method, className: stClass.name, selector: method.selector, side: side, source: source)
        }
        stClass[side][method.selector] = method
        catalogDirty = true
        return method.selector
    }

    private func withCompiler<T>(_ source: String, selector: String, decode: (Value) throws -> T) throws -> T {
        guard source.utf8.count <= 262_144 else { throw SmalltalkError("Source code exceeds the 256 KiB limit.") }
        let workspace = SmalltalkRuntime(bootstrap: false, compilationMode: true)
        workspace.memory.stressCollection = memory.stressCollection
        workspace.executionCancellation = executionCancellation
        for name in Self.compilerClassNames {
            guard let original = classes[name], original.superclass?.name == "Object",
                  let parent = workspace.classes["Object"] else { throw SmalltalkError("Compiler class \(name) is missing.") }
            let copy = STClass(name, superclass: parent, fields: original.ownFields)
            copy.methods = original.methods
            copy.classMethods = original.classMethods
            workspace.classes[name] = copy
            workspace.globals[name] = .classObject(copy)
        }
        guard let compiler = workspace.globals["STCompiler"] else { throw SmalltalkError("The Smalltalk compiler is missing.") }
        let instance = try workspace.send(compiler, "new", [])
        return try workspace.withRoots([instance]) { roots in
            let output = try workspace.send(instance, selector, [.string(source)])
            roots.add(output)
            return try decode(output)
        }
    }
}

/// Decodes the Smalltalk compiler's tagged arrays into the VM's executable data.
/// This boundary accepts data only. It never parses Smalltalk source.
private enum CompilerOutput {
    static func body(_ value: Value) throws -> Body { try body(value, depth: 1) }

    private static func body(_ value: Value, depth: Int) throws -> Body {
        let fields = try parts(value, count: 2)
        return Body(temporaries: try names(fields[0]), expressions: try expressions(fields[1], depth: depth))
    }

    static func parts(_ value: Value, count: Int? = nil) throws -> [Value] {
        guard case .array(let array) = value, count == nil || array.elements.count == count else { throw invalid() }
        return array.elements
    }

    static func string(_ value: Value) throws -> String {
        guard case .string(let text) = value else { throw invalid() }
        return text
    }

    static func names(_ value: Value) throws -> [String] { try parts(value).map(string) }

    private static func expressions(_ value: Value, depth: Int) throws -> [Expression] {
        try parts(value).map { try expression($0, depth: depth) }
    }

    private static func expression(_ value: Value, depth: Int) throws -> Expression {
        guard depth <= 128 else { throw SmalltalkError("Expression is nested too deeply.") }
        let fields = try parts(value, count: 5)
        guard case .symbol(let tag) = fields[0],
              case .integer(let line) = fields[1], case .integer(let column) = fields[2],
              line > 0, column > 0 else { throw invalid() }
        let first = fields[3], second = fields[4], next = depth + 1
        let kind: ExpressionKind
        switch tag {
        case "literal": kind = .literal(try literal(first, depth: 0))
        case "variable": kind = .variable(try string(first))
        case "assignment": kind = .assignment(try string(first), try expression(second, depth: next))
        case "returnValue": kind = .returnValue(try expression(first, depth: next))
        case "send":
            let send = try message(second, depth: next)
            kind = .send(try expression(first, depth: next), send.selector, send.arguments)
        case "cascade":
            let sends = try parts(second).map { try message($0, depth: next) }
            kind = .cascade(try expression(first, depth: next), sends)
        case "block": kind = .block(try names(first), try body(second, depth: next))
        default: throw invalid()
        }
        return try Expression(kind: kind, position: SourcePosition(line: Int(line), column: Int(column)))
    }

    private static func message(_ value: Value, depth: Int) throws -> Message {
        let fields = try parts(value, count: 2)
        return Message(selector: try string(fields[0]), arguments: try expressions(fields[1], depth: depth))
    }

    private static func literal(_ value: Value, depth: Int) throws -> Literal {
        guard depth <= 32 else { throw SmalltalkError("Literal is nested too deeply.") }
        switch value {
        case .integer(let number): return .integer(number)
        case .largeInteger(let number): return .largeInteger(number)
        case .string(let text): return .string(text)
        case .symbol(let name): return .symbol(name)
        case .boolean(let value): return .boolean(value)
        case .nilValue: return .nilValue
        case .character(let codePoint): return .character(codePoint)
        case .float(let number): return .float(number)
        case .array(let array): return .array(try array.elements.map { try literal($0, depth: depth + 1) })
        default: throw invalid()
        }
    }

    private static func invalid() -> SmalltalkError { SmalltalkError("The Smalltalk compiler produced an invalid syntax tree.") }
}

/// Shared checks for executable code, whether it comes from the compiler or an
/// image. They validate shape and operands without reconstructing source text.
enum CodeValidator {
    private static let reserved = ["self", "super", "true", "false", "nil", "thisContext"]
    private static let binary = "+-*/\\~<>=@%,&?!|"

    static func identifier(_ name: String) -> Bool {
        guard let first = name.first, first.isLetter || first == "_" else { return false }
        return name.dropFirst().allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    static func validNames(_ names: [String]) -> Bool {
        Set(names).count == names.count && names.allSatisfy {
            identifier($0) && !reserved.contains($0)
        }
    }

    static func arity(of selector: String) -> Int {
        let keywords = selector.filter { $0 == ":" }.count
        if keywords > 0 { return keywords }
        return selector.first.map { binary.contains($0) } == true ? 1 : 0
    }

    static func checkSelector(_ selector: String, arguments: Int) throws {
        if selector.contains(":") {
            let parts = selector.split(separator: ":", omittingEmptySubsequences: false)
            if selector.hasSuffix(":"), parts.count - 1 == arguments, parts.dropLast().allSatisfy({ identifier(String($0)) }) { return }
        } else if arguments == 0 && identifier(selector) {
            return
        } else if arguments == 1 && !selector.isEmpty && selector.allSatisfy({ binary.contains($0) }) {
            return
        }
        throw SmalltalkError("Invalid selector or argument count for \(selector).")
    }

    static func check(_ method: Method) throws {
        try checkSelector(method.selector, arguments: method.parameters.count)
        guard validNames(method.parameters), Set(method.parameters).isDisjoint(with: method.body.temporaries) else {
            throw SmalltalkError("Invalid method arguments.")
        }
        try method.body.validate(parameters: method.parameters)
    }

    static func check(_ body: Body, parameters: [String] = [], outerArguments: Set<String> = []) throws {
        guard validNames(body.temporaries) else { throw SmalltalkError("Invalid local variables.") }
        let arguments = outerArguments.subtracting(body.temporaries).union(parameters)
        var pending = body.expressions.enumerated().map { ($0.element, $0.offset == body.expressions.count - 1) }
        while let (expression, allowsReturn) = pending.popLast() {
            guard expression.position.line > 0, expression.position.column > 0 else { throw SmalltalkError("Invalid source position.") }
            switch expression.kind {
            case .block(let parameters, let body):
                guard validNames(parameters), validNames(body.temporaries), Set(parameters).isDisjoint(with: body.temporaries) else {
                    throw SmalltalkError("Invalid block variables.")
                }
                try check(body, parameters: parameters, outerArguments: arguments)
            case .variable(let name):
                guard identifier(name) else { throw SmalltalkError("Invalid variable.") }
            case .assignment(let name, let value):
                guard identifier(name) else { throw SmalltalkError("Invalid assignment target.") }
                guard !arguments.contains(name) else {
                    throw SmalltalkError("Argument \(name) cannot be reassigned.", at: expression.position)
                }
                pending.append((value, false))
            case .returnValue(let value):
                guard allowsReturn else { throw SmalltalkError("A return must be the last statement.", at: expression.position) }
                pending.append((value, false))
            case .send(let receiver, let selector, let args):
                try checkSelector(selector, arguments: args.count)
                pending.append((receiver, false))
                pending.append(contentsOf: args.map { ($0, false) })
            case .cascade(let receiver, let messages):
                guard !messages.isEmpty else { throw SmalltalkError("Empty cascade.") }
                pending.append((receiver, false))
                for message in messages {
                    try checkSelector(message.selector, arguments: message.arguments.count)
                    pending.append(contentsOf: message.arguments.map { ($0, false) })
                }
            case .literal(let value):
                var literals = [(value, 0)]
                while let (literal, depth) = literals.popLast() {
                    guard depth <= 32 else { throw SmalltalkError("Literal is nested too deeply.") }
                    if case .array(let elements) = literal {
                        literals.append(contentsOf: elements.map { ($0, depth + 1) })
                    }
                }
            }
        }
    }
}
