import Foundation

extension SmalltalkRuntime {
    func evaluate(_ expression: Expression, context: Context) throws -> Value {
        try enter()
        defer { depth -= 1 }
        do {
            switch expression.kind {
            case .literal(let literal): return try value(literal)
            case .variable(let name): return try variable(name, context: context)
            case .assignment(let name, let expression):
                let value = try evaluate(expression, context: context)
                try assign(name, value: value, context: context)
                return value
            case .send(let receiverExpression, let selector, let arguments):
                let (receiver, lookup) = try messageReceiver(receiverExpression, context: context)
                return try evaluateMessage(receiver, selector, arguments, context: context, startingAt: lookup)
            case .cascade(let receiverExpression, let branches):
                let (receiver, lookup) = try messageReceiver(receiverExpression, context: context)
                return try withRoots([receiver]) { _ in
                    var result = receiver
                    for branch in branches {
                        result = receiver
                        for (index, message) in branch.enumerated() {
                            result = try evaluateMessage(result, message.selector, message.arguments, context: context,
                                                         startingAt: index == 0 ? lookup : .normal)
                        }
                    }
                    return result
                }
            case .block(let parameters, let body):
                return .block(try block(parameters: parameters, body: BytecodeBody.lower(body), context: context, referenceBody: body))
            case .returnValue(let expression):
                try checkHomeForReturn(context)
                throw ReturnSignal(value: try evaluate(expression, context: context), homeID: context.homeID)
            }
        } catch var error as SmalltalkError {
            error.locate(at: expression.position, in: context)
            throw error
        }
    }

    private func evaluateMessage(_ receiver: Value, _ selector: String, _ arguments: [Expression], context: Context, startingAt lookup: MessageLookup) throws -> Value {
        // Earlier operands stay live while a later argument may redefine a class.
        let rootCount = evaluationRoots.count
        evaluationRoots.append(receiver)
        pendingMessages.append((receiver, lookup))
        defer {
            evaluationRoots.removeSubrange(rootCount...)
            pendingMessages.removeLast()
        }
        var values: [Value] = []
        for argument in arguments {
            let value = try evaluate(argument, context: context)
            values.append(value)
            evaluationRoots.append(value)
        }
        return try send(receiver, selector, values, startingAt: lookup)
    }

    private func messageReceiver(_ expression: Expression, context: Context) throws -> (Value, MessageLookup) {
        if case .variable("super") = expression.kind { return (context.receiver, try superLookup(context)) }
        return (try evaluate(expression, context: context), .normal)
    }
}
