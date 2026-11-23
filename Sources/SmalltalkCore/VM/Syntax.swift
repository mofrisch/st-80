import Foundation

public struct SourcePosition: Sendable, Equatable, Codable {
    public let line: Int
    public let column: Int
}

public struct SmalltalkError: Error, LocalizedError, Sendable {
    public let message: String
    public var position: SourcePosition?

    public var errorDescription: String? {
        if let position { return "Zeile \(position.line), Spalte \(position.column): \(message)" }
        return message
    }

    init(_ message: String, at position: SourcePosition? = nil) {
        self.message = message
        self.position = position
    }
}

indirect enum Literal: Codable, Sendable {
    case integer(Int64), string(String), symbol(String), array([Literal])
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
        guard height <= 128 else { throw SmalltalkError("Ausdruck ist zu tief verschachtelt.", at: position) }
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
    let selector: String
    let parameters: [String]
    let body: Body
    let source: String
}
