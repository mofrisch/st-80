import Foundation

public struct SourcePosition: Sendable, Equatable, Codable {
    public let line: Int
    public let column: Int
}

public struct SmalltalkError: Error, LocalizedError, Sendable {
    public let message: String
    public var position: SourcePosition?
    let isTestFailure: Bool

    public var errorDescription: String? {
        if let position { return "Line \(position.line), column \(position.column): \(message)" }
        return message
    }

    init(_ message: String, at position: SourcePosition? = nil, isTestFailure: Bool = false) {
        self.message = message
        self.position = position
        self.isTestFailure = isTestFailure
    }

    mutating func locate(at position: SourcePosition, in context: Context) {
        guard self.position == nil else { return }
        // Report assertion calls in the test rather than inside TestCase's helpers.
        if isTestFailure, context.homeClass?.name == "TestCase" { return }
        self.position = position
    }
}

indirect enum Literal: Codable, Sendable {
    case integer(Int64), string(String), symbol(String), array([Literal])
    case largeInteger(BigInteger)
    case scaledDecimal(ScaledDecimal)
    case boolean(Bool), nilValue, character(UInt32), float(Double)
}

struct Expression: Codable, Sendable {
    let kind: ExpressionKind
    let position: SourcePosition
    let height: Int

    private enum CodingKeys: String, CodingKey { case kind, position }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(kind: values.decode(ExpressionKind.self, forKey: .kind), position: values.decode(SourcePosition.self, forKey: .position))
    }

    init(kind: ExpressionKind, position: SourcePosition) throws {
        self.kind = kind
        self.position = position
        switch kind {
        case .literal, .variable: height = 1
        case .assignment(_, let value), .returnValue(let value): height = value.height + 1
        case .send(let receiver, _, let arguments): height = max(receiver.height, arguments.map(\.height).max() ?? 0) + 1
        case .cascade(let receiver, let messages): height = max(receiver.height, messages.flatMap(\.arguments).map(\.height).max() ?? 0) + 1
        case .block(_, let body): height = (body.expressions.map(\.height).max() ?? 0) + 1
        }
        guard height <= 128 else { throw SmalltalkError("Expression is nested too deeply.", at: position) }
    }
}

indirect enum ExpressionKind: Codable, Sendable {
    case literal(Literal), variable(String), assignment(String, Expression)
    case send(Expression, String, [Expression])
    case cascade(Expression, [Message])
    case block([String], Body), returnValue(Expression)
}

struct Message: Codable, Sendable {
    let selector: String
    let arguments: [Expression]
}

struct Body: Codable, Sendable {
    let temporaries: [String]
    let expressions: [Expression]
}

struct Method: Sendable {
    let identity = UUID()
    let selector: String
    let parameters: [String]
    let body: BytecodeBody
    let source: String
    let referenceBody: Body?

    init(selector: String, parameters: [String], body: BytecodeBody, source: String, referenceBody: Body? = nil) {
        self.selector = selector
        self.parameters = parameters
        self.body = body
        self.source = source
        self.referenceBody = referenceBody
    }
}
