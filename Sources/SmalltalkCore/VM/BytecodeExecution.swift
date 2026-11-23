enum BytecodeOperand {
    case value(Value)
    case receiver(Value, MessageLookup)

    var value: Value {
        switch self {
        case .value(let value), .receiver(let value, _): return value
        }
    }
}

extension SmalltalkRuntime {
    func executeBytecode(_ body: BytecodeBody, context: Context) throws -> Value {
        let base = bytecodeOperands.count
        defer { bytecodeOperands.removeSubrange(base...) }

        // Each invocation owns the operand segment starting at base. A send
        // keeps its operands in that segment until nested execution finishes.
        for instruction in body.instructions {
            do {
                try tick()
                try debugger?.before(instruction, runtime: self)
                switch instruction.operation {
                case .pushLiteral(let literal):
                    bytecodeOperands.append(.value(try value(literal)))
                case .load(let name):
                    bytecodeOperands.append(.value(try variable(name, context: context)))
                case .store(let name):
                    try assign(name, value: bytecodeOperands[bytecodeOperands.count - 1].value, context: context)
                case .pop:
                    bytecodeOperands.removeLast()
                case .duplicate:
                    let operand = bytecodeOperands[bytecodeOperands.count - 1]
                    bytecodeOperands.append(operand)
                case .prepareSend(let isSuper):
                    let lookup = try isSuper ? superLookup(context) : .normal
                    let index = bytecodeOperands.count - 1
                    bytecodeOperands[index] = .receiver(bytecodeOperands[index].value, lookup)
                case .send(let selector):
                    let argumentCount = CodeValidator.arity(of: selector)
                    let receiverIndex = bytecodeOperands.count - argumentCount - 1
                    guard case .receiver(let receiver, let lookup) = bytecodeOperands[receiverIndex] else {
                        throw SmalltalkError("Invalid bytecode message receiver.")
                    }
                    let arguments = bytecodeOperands[(receiverIndex + 1)...].map(\.value)
                    let result = try send(receiver, selector, arguments, startingAt: lookup)
                    bytecodeOperands.removeSubrange(receiverIndex...)
                    bytecodeOperands.append(.value(result))
                case .discardReceiverBelowResult:
                    bytecodeOperands.remove(at: bytecodeOperands.count - 2)
                case .makeBlock(let parameters, let body):
                    let closure = try block(parameters: parameters, body: body, context: context)
                    bytecodeOperands.append(.value(.block(closure)))
                case .checkReturn:
                    try checkHomeForReturn(context)
                case .returnFromHome:
                    throw ReturnSignal(value: bytecodeOperands[bytecodeOperands.count - 1].value, homeID: context.homeID)
                case .finish:
                    return bytecodeOperands[bytecodeOperands.count - 1].value
                }
            } catch var error as SmalltalkError {
                if error.position == nil { error.position = instruction.position }
                debugger?.report(error, at: instruction, runtime: self)
                throw error
            } catch {
                debugger?.report(error, at: instruction, runtime: self)
                throw error
            }
        }
        throw SmalltalkError("Bytecode ended without a final instruction.")
    }
}
