/// Linear executable code. Nested blocks carry their own instruction stream.
struct BytecodeBody: Codable, Sendable {
    let temporaries: [String]
    let instructions: [BytecodeInstruction]

    func disassembly(parameters: [String]) -> String {
        var lines: [String] = []
        if !parameters.isEmpty {
            lines.append("Parameters  \(parameters.joined(separator: ", "))")
        }
        appendDisassembly(to: &lines, indent: "")
        return lines.joined(separator: "\n")
    }

    private func appendDisassembly(to lines: inout [String], indent: String) {
        if !temporaries.isEmpty {
            lines.append("\(indent)Temporaries  \(temporaries.joined(separator: ", "))")
        }
        for (index, instruction) in instructions.enumerated() {
            let offset = String(index)
            let padding = String(repeating: "0", count: max(0, 4 - offset.count))
            lines.append("\(indent)\(padding)\(offset)  \(instruction.operation.disassemblyText)")
            if case .makeBlock(_, let body) = instruction.operation {
                body.appendDisassembly(to: &lines, indent: indent + "    ")
            }
        }
    }

    static func lower(_ body: Body) -> Self {
        var instructions: [BytecodeInstruction] = []
        for (index, expression) in body.expressions.enumerated() {
            if index > 0 {
                instructions.append(.init(operation: .pop, position: expression.position))
            }
            lower(expression, into: &instructions)
        }
        let end = body.expressions.last?.position ?? SourcePosition(line: 1, column: 1)
        if instructions.isEmpty { instructions.append(.init(operation: .load("nil"), position: end)) }
        instructions.append(.init(operation: .finish, position: end))
        return Self(temporaries: body.temporaries, instructions: instructions)
    }

    private static func lower(_ expression: Expression, into instructions: inout [BytecodeInstruction]) {
        let position = expression.position
        switch expression.kind {
        case .literal(let literal):
            instructions.append(.init(operation: .pushLiteral(literal), position: position))
        case .variable(let name):
            instructions.append(.init(operation: .load(name), position: position))
        case .assignment(let name, let value):
            lower(value, into: &instructions)
            instructions.append(.init(operation: .store(name), position: position))
        case .send(let receiver, let selector, let arguments):
            lowerReceiver(receiver, position: position, into: &instructions)
            for argument in arguments { lower(argument, into: &instructions) }
            instructions.append(.init(operation: .send(selector), position: position))
        case .cascade(let receiver, let branches):
            lowerReceiver(receiver, position: position, into: &instructions)
            for (index, branch) in branches.enumerated() {
                if index > 0 { instructions.append(.init(operation: .pop, position: position)) }
                instructions.append(.init(operation: .duplicate, position: position))
                for (messageIndex, message) in branch.enumerated() {
                    if messageIndex > 0 { instructions.append(.init(operation: .prepareSend(isSuper: false), position: position)) }
                    for argument in message.arguments { lower(argument, into: &instructions) }
                    instructions.append(.init(operation: .send(message.selector), position: position))
                }
            }
            instructions.append(.init(operation: .discardReceiverBelowResult, position: position))
        case .block(let parameters, let body):
            instructions.append(.init(operation: .makeBlock(parameters, lower(body)), position: position))
        case .returnValue(let value):
            instructions.append(.init(operation: .checkReturn, position: position))
            lower(value, into: &instructions)
            instructions.append(.init(operation: .returnFromHome, position: position))
        }
    }

    private static func lowerReceiver(_ receiver: Expression, position: SourcePosition, into instructions: inout [BytecodeInstruction]) {
        // Capture super's lookup class before evaluation of any arguments. An
        // argument may attempt to edit the class hierarchy while we are here.
        if case .variable("super") = receiver.kind {
            instructions.append(.init(operation: .load("self"), position: position))
            instructions.append(.init(operation: .prepareSend(isSuper: true), position: position))
        } else {
            lower(receiver, into: &instructions)
            instructions.append(.init(operation: .prepareSend(isSuper: false), position: position))
        }
    }

    func validate(parameters: [String]) throws {
        var budget = 1_048_576
        try validate(parameters: parameters, depth: 1, remainingInstructions: &budget)
    }

    private enum OperandKind { case value, receiver }

    private func validate(parameters: [String], depth: Int, remainingInstructions: inout Int) throws {
        guard depth <= 128, !instructions.isEmpty, instructions.count <= remainingInstructions else {
            throw SmalltalkError("Invalid bytecode size or nesting.")
        }
        remainingInstructions -= instructions.count
        guard CodeValidator.validNames(parameters), CodeValidator.validNames(temporaries),
              IdentifierKey.set(parameters).isDisjoint(with: IdentifierKey.set(temporaries)) else {
            throw SmalltalkError("Invalid bytecode variable declarations.")
        }
        var stack: [OperandKind] = []
        var returnChecks: [Int] = []
        for (index, instruction) in instructions.enumerated() {
            let position = instruction.position
            guard position.line > 0, position.column > 0 else {
                throw SmalltalkError("Invalid bytecode source position.")
            }
            func invalidStack() -> SmalltalkError { SmalltalkError("Invalid bytecode operand stack.", at: position) }
            switch instruction.operation {
            case .pushLiteral(let literal):
                try Self.validate(literal, depth: 0)
                stack.append(.value)
            case .load(let name):
                guard CodeValidator.identifier(name) else { throw SmalltalkError("Invalid bytecode variable.", at: position) }
                stack.append(.value)
            case .store(let name):
                guard CodeValidator.identifier(name) else { throw SmalltalkError("Invalid bytecode assignment target.", at: position) }
                guard stack.last == .value else { throw invalidStack() }
            case .pop:
                guard stack.popLast() == .value else { throw invalidStack() }
            case .duplicate:
                guard stack.last == .receiver else { throw invalidStack() }
                stack.append(.receiver)
            case .prepareSend(let isSuper):
                if isSuper {
                    guard index > 0, case .load("self") = instructions[index - 1].operation else {
                        throw SmalltalkError("Invalid bytecode super receiver.", at: position)
                    }
                }
                guard stack.popLast() == .value else { throw invalidStack() }
                stack.append(.receiver)
            case .send(let selector):
                let arity = CodeValidator.arity(of: selector)
                try CodeValidator.checkSelector(selector, arguments: arity)
                let receiver = stack.count - arity - 1
                guard receiver >= 0, stack[receiver] == .receiver,
                      stack.suffix(arity).allSatisfy({ $0 == .value }) else { throw invalidStack() }
                stack.removeLast(arity + 1)
                stack.append(.value)
            case .discardReceiverBelowResult:
                guard stack.popLast() == .value, stack.popLast() == .receiver else { throw invalidStack() }
                stack.append(.value)
            case .makeBlock(let parameters, let body):
                try body.validate(parameters: parameters, depth: depth + 1, remainingInstructions: &remainingInstructions)
                stack.append(.value)
            case .checkReturn:
                returnChecks.append(stack.count)
            case .returnFromHome:
                // Linear validation keeps the result on the abstract stack so
                // the compiler's unreachable instructions are also checked.
                guard let depth = returnChecks.popLast(), stack.count == depth + 1,
                      stack.last == .value else { throw invalidStack() }
            case .finish:
                guard index == instructions.count - 1, stack == [.value], returnChecks.isEmpty else {
                    throw invalidStack()
                }
                return
            }
        }
        throw SmalltalkError("The bytecode body has no finish instruction.")
    }

    private static func validate(_ literal: Literal, depth: Int) throws {
        guard depth <= 32 else { throw SmalltalkError("Bytecode literal is nested too deeply.") }
        switch literal {
        case .character(let codePoint) where Unicode.Scalar(codePoint) == nil:
            throw SmalltalkError("Invalid character literal in bytecode.")
        case .float(let number) where !number.isFinite:
            throw SmalltalkError("Invalid floating-point literal in bytecode.")
        case .array(let elements):
            for element in elements { try validate(element, depth: depth + 1) }
        default: break
        }
    }

    /// Inspect executable code when live class editing removes a slot. Block
    /// parameters and local declarations shadow fields just as in source code.
    func reference(to removed: Set<IdentifierKey>, excluding outerNames: Set<IdentifierKey>) -> String? {
        let locals = outerNames.union(IdentifierKey.set(temporaries))
        for instruction in instructions {
            switch instruction.operation {
            case .load(let name), .store(let name):
                let key = IdentifierKey(name)
                if removed.contains(key), !locals.contains(key) { return name }
            case .makeBlock(let parameters, let body):
                if let reference = body.reference(to: removed, excluding: locals.union(IdentifierKey.set(parameters))) { return reference }
            default:
                break
            }
        }
        return nil
    }
}

struct BytecodeInstruction: Codable, Sendable {
    let operation: BytecodeOperation
    let position: SourcePosition
}

enum BytecodeOperation: Codable, Sendable {
    case pushLiteral(Literal)
    case load(String)
    case store(String)
    case pop
    case duplicate
    case prepareSend(isSuper: Bool)
    case send(String)
    case discardReceiverBelowResult
    case makeBlock([String], BytecodeBody)
    case checkReturn
    case returnFromHome
    case finish
}

extension BytecodeOperation {
    var disassemblyText: String {
        switch self {
        case .pushLiteral(let literal): return "PUSH_LITERAL \(literal.disassemblyText)"
        case .load(let name): return "LOAD \(name)"
        case .store(let name): return "STORE \(name)"
        case .pop: return "POP"
        case .duplicate: return "DUPLICATE"
        case .prepareSend(let isSuper): return "PREPARE_SEND \(isSuper ? "super" : "normal")"
        case .send(let selector): return "SEND \(selector)"
        case .discardReceiverBelowResult: return "DISCARD_RECEIVER_BELOW_RESULT"
        case .makeBlock(let parameters, _): return "MAKE_BLOCK (\(parameters.joined(separator: ", ")))"
        case .checkReturn: return "CHECK_RETURN"
        case .returnFromHome: return "RETURN_FROM_HOME"
        case .finish: return "FINISH"
        }
    }
}

private extension Literal {
    var disassemblyText: String {
        switch self {
        case .integer(let value): return String(value)
        case .largeInteger(let value): return value.description
        case .scaledDecimal(let value): return value.description
        case .string(let value): return Self.quote(value)
        case .boolean(let value): return String(value)
        case .nilValue: return "nil"
        case .character(let value): return "$" + Self.quote(Unicode.Scalar(value).map(String.init) ?? "�")
        case .float(let value): return SmalltalkRuntime.floatLiteralText(value)
        case .symbol(let value):
            let arity = CodeValidator.arity(of: value)
            if (try? CodeValidator.checkSelector(value, arguments: arity)) != nil {
                return "#\(value)"
            }
            return "#\(Self.quote(value))"
        case .array(let values):
            return "#(\(values.map(\.disassemblyText).joined(separator: " ")))"
        }
    }

    static func quote(_ value: String) -> String {
        var quoted = "'"
        for scalar in value.unicodeScalars {
            switch scalar {
            case "'": quoted += "''"
            case "\\": quoted += "\\\\"
            case "\n": quoted += "\\n"
            case "\r": quoted += "\\r"
            case "\t": quoted += "\\t"
            case _ where scalar.properties.generalCategory == .control || scalar == "\u{2028}" || scalar == "\u{2029}":
                quoted += "\\u{\(String(scalar.value, radix: 16, uppercase: true))}"
            default: quoted.unicodeScalars.append(scalar)
            }
        }
        quoted += "'"
        return quoted
    }
}
