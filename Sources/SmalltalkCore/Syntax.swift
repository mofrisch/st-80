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

enum TokenKind: Equatable {
    case integer(Int64), string(String), symbol(String), identifier(String), keyword(String)
    case minimumMagnitude
    case binary(String), assign, period, semicolon, caret, colon, bar
    case leftParen, rightParen, leftBracket, rightBracket, arrayStart, end
}

struct Token {
    let kind: TokenKind
    let position: SourcePosition
}

struct Lexer {
    private let characters: [Character]
    private var index = 0
    private var line = 1
    private var column = 1

    init(_ source: String) { characters = Array(source) }

    mutating func scan() throws -> [Token] {
        var tokens: [Token] = []
        while index < characters.count {
            let c = characters[index]
            if c.isWhitespace { advance(); continue }
            let position = SourcePosition(line: line, column: column)
            if c == "\"" {
                advance()
                while peek() != nil && peek() != "\"" { advance() }
                guard peek() != nil else { throw SmalltalkError("Kommentar ist nicht geschlossen.", at: position) }
                advance()
                continue
            }
            let kind: TokenKind
            if c.isASCII && c.isNumber {
                var digits = ""
                while let next = peek(), next.isASCII && next.isNumber { digits.append(next); advance() }
                if digits == "9223372036854775808" { kind = .minimumMagnitude }
                else if let number = Int64(digits) { kind = .integer(number) }
                else {
                    throw SmalltalkError("Ganzzahl ist zu groß (64-Bit-Grenze).", at: position)
                }
            } else if isIdentifierStart(c) {
                let name = readIdentifier()
                if peek() == ":" && peek(1) != "=" { advance(); kind = .keyword(name + ":") }
                else { kind = .identifier(name) }
            } else {
                advance()
                switch c {
                case "'": kind = .string(try readString(at: position))
                case "#":
                    if peek() == "(" { advance(); kind = .arrayStart }
                    else if peek() == "'" { advance(); kind = .symbol(try readString(at: position)) }
                    else if let next = peek(), isIdentifierStart(next) {
                        var name = readIdentifier()
                        while peek() == ":" {
                            name.append(":"); advance()
                            if let next = peek(), isIdentifierStart(next) { name += readIdentifier() }
                            else { break }
                        }
                        kind = .symbol(name)
                    } else if let next = peek(), isBinary(next) {
                        var name = ""
                        while let next = peek(), isBinary(next) { name.append(next); advance() }
                        kind = .symbol(name)
                    } else { throw SmalltalkError("Nach # wird ein Symbol oder ( erwartet.", at: position) }
                case ":":
                    if peek() == "=" { advance(); kind = .assign }
                    else { kind = .colon }
                case ".": kind = .period
                case ";": kind = .semicolon
                case "^": kind = .caret
                case "|": kind = .bar
                case "(": kind = .leftParen
                case ")": kind = .rightParen
                case "[": kind = .leftBracket
                case "]": kind = .rightBracket
                default:
                    if isBinary(c) {
                        var name = String(c)
                        while let next = peek(), isBinary(next) { name.append(next); advance() }
                        kind = .binary(name)
                    } else { throw SmalltalkError("Unbekanntes Zeichen: \(c)", at: position) }
                }
            }
            tokens.append(Token(kind: kind, position: position))
        }
        tokens.append(Token(kind: .end, position: SourcePosition(line: line, column: column)))
        return tokens
    }

    private func peek(_ offset: Int = 0) -> Character? {
        index + offset < characters.count ? characters[index + offset] : nil
    }

    private mutating func advance() {
        if characters[index] == "\n" || characters[index] == "\r" || characters[index] == "\r\n" { line += 1; column = 1 }
        else { column += 1 }
        index += 1
    }

    private func isIdentifierStart(_ c: Character) -> Bool { c.isLetter || c == "_" }
    private func isBinary(_ c: Character) -> Bool { "+-*/\\~<>=@%,&?!".contains(c) }

    private mutating func readIdentifier() -> String {
        var name = ""
        while let c = peek(), isIdentifierStart(c) || c.isNumber { name.append(c); advance() }
        return name
    }

    private mutating func readString(at position: SourcePosition) throws -> String {
        var value = ""
        while let c = peek() {
            advance()
            if c == "'" {
                if peek() == "'" { value.append("'"); advance() }
                else { return value }
            } else { value.append(c) }
        }
        throw SmalltalkError("String ist nicht geschlossen.", at: position)
    }
}

indirect enum Literal: Codable {
    case integer(Int64), string(String), symbol(String), array([Literal])
}

struct Expression: Codable {
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

indirect enum ExpressionKind: Codable {
    case literal(Literal), variable(String), assignment(String, Expression)
    case send(Expression, String, [Expression])
    case cascade(Expression, [Message])
    case block([String], Body), returnValue(Expression)
}

struct Message: Codable {
    let selector: String
    let arguments: [Expression]
}

struct Body: Codable {
    let temporaries: [String]
    let expressions: [Expression]
}

struct Method {
    let selector: String
    let parameters: [String]
    let body: Body
    let source: String
}

struct Parser {
    private let tokens: [Token]
    private var index = 0
    private var nesting = 0

    init(_ source: String) throws {
        guard source.utf8.count <= 262_144 else { throw SmalltalkError("Quelltext ist zu groß (maximal 256 KiB).") }
        var lexer = Lexer(source)
        tokens = try lexer.scan()
        // Reject deep delimiters before entering the recursive-descent parser.
        var delimiterDepth = 0
        for token in tokens {
            switch token.kind {
            case .leftParen, .leftBracket, .arrayStart: delimiterDepth += 1
            case .rightParen, .rightBracket: delimiterDepth -= 1
            default: break
            }
            guard delimiterDepth <= 32 else { throw SmalltalkError("Quelltext ist zu tief verschachtelt (maximal 32 Ebenen).", at: token.position) }
        }
    }

    mutating func workspace() throws -> Body {
        let result = try body(until: .end)
        try expect(.end)
        return result
    }

    mutating func method(source: String) throws -> Method {
        var selector = ""
        var parameters: [String] = []
        switch current.kind {
        case .identifier(let name): selector = name; advance()
        case .binary(let name): selector = name; advance(); parameters.append(try identifier())
        case .keyword:
            while case .keyword(let part) = current.kind {
                selector += part; advance(); parameters.append(try identifier())
            }
        default: throw error("Methodenkopf erwartet, zum Beispiel increment oder add: amount.")
        }
        try validateNames(parameters)
        let result = try workspace()
        guard Set(parameters).isDisjoint(with: result.temporaries) else { throw error("Argument und lokale Variable haben denselben Namen.") }
        return Method(selector: selector, parameters: parameters, body: result, source: source)
    }

    private var current: Token { tokens[index] }
    private mutating func advance() { if index < tokens.count - 1 { index += 1 } }
    private func error(_ message: String) -> SmalltalkError { SmalltalkError(message, at: current.position) }

    private mutating func expect(_ kind: TokenKind) throws {
        guard current.kind == kind else { throw error("\(label(kind)) erwartet, gefunden: \(label(current.kind)).") }
        advance()
    }

    private func label(_ kind: TokenKind) -> String {
        switch kind {
        case .end: "Ende des Quelltexts"
        case .rightBracket: "]"
        case .rightParen: ")"
        case .bar: "|"
        case .period: "."
        default: String(describing: kind)
        }
    }

    private mutating func identifier() throws -> String {
        guard case .identifier(let name) = current.kind else { throw error("Variablenname erwartet.") }
        advance()
        return name
    }

    private func validateNames(_ names: [String]) throws {
        let reserved: Set<String> = ["self", "super", "true", "false", "nil", "thisContext"]
        guard names.allSatisfy({ !reserved.contains($0) && $0.first?.isLowercase == true }) else {
            throw error("Variablennamen müssen klein beginnen und dürfen keine Pseudovariablen sein.")
        }
        guard Set(names).count == names.count else { throw error("Variablenname ist doppelt deklariert.") }
    }

    private mutating func body(until terminator: TokenKind) throws -> Body {
        var temporaries: [String] = []
        if current.kind == .bar {
            advance()
            while case .identifier = current.kind { temporaries.append(try identifier()) }
            try expect(.bar)
        }
        try validateNames(temporaries)
        var expressions: [Expression] = []
        while current.kind != terminator && current.kind != .end {
            expressions.append(try expression())
            if current.kind == .period { advance() }
            else if current.kind != terminator { throw error("Zwischen Ausdrücken wird ein Punkt erwartet.") }
        }
        return Body(temporaries: temporaries, expressions: expressions)
    }

    private mutating func expression() throws -> Expression {
        nesting += 1
        defer { nesting -= 1 }
        guard nesting <= 128 else { throw error("Ausdruck ist zu tief verschachtelt.") }
        let position = current.position
        if current.kind == .caret {
            advance()
            return try Expression(kind: .returnValue(try expression()), position: position)
        }
        if case .identifier(let name) = current.kind, tokens[index + 1].kind == .assign {
            advance(); advance()
            return try Expression(kind: .assignment(name, try expression()), position: position)
        }
        let first = try keywordExpression()
        guard current.kind == .semicolon else { return first }
        guard case .send(let receiver, let selector, let arguments) = first.kind else {
            throw error("Vor einer Kaskade muss eine Nachricht stehen.")
        }
        var messages = [Message(selector: selector, arguments: arguments)]
        while current.kind == .semicolon {
            advance()
            messages.append(try cascadeMessage())
        }
        return try Expression(kind: .cascade(receiver, messages), position: position)
    }

    private mutating func keywordExpression() throws -> Expression {
        var receiver = try binaryExpression()
        if case .keyword = current.kind {
            var selector = ""
            var arguments: [Expression] = []
            while case .keyword(let part) = current.kind {
                selector += part; advance(); arguments.append(try binaryExpression())
            }
            receiver = try Expression(kind: .send(receiver, selector, arguments), position: receiver.position)
        }
        return receiver
    }

    private mutating func binaryExpression() throws -> Expression {
        var receiver = try unaryExpression()
        while case .binary(let selector) = current.kind {
            advance()
            receiver = try Expression(kind: .send(receiver, selector, [try unaryExpression()]), position: receiver.position)
        }
        return receiver
    }

    private mutating func unaryExpression() throws -> Expression {
        var receiver = try primary()
        while case .identifier(let selector) = current.kind {
            advance()
            receiver = try Expression(kind: .send(receiver, selector, []), position: receiver.position)
        }
        return receiver
    }

    private mutating func cascadeMessage() throws -> Message {
        switch current.kind {
        case .identifier(let selector): advance(); return Message(selector: selector, arguments: [])
        case .binary(let selector): advance(); return Message(selector: selector, arguments: [try unaryExpression()])
        case .keyword:
            var selector = ""
            var arguments: [Expression] = []
            while case .keyword(let part) = current.kind {
                selector += part; advance(); arguments.append(try binaryExpression())
            }
            return Message(selector: selector, arguments: arguments)
        default: throw error("Nach ; wird eine Nachricht erwartet.")
        }
    }

    private mutating func primary() throws -> Expression {
        let position = current.position
        let kind: ExpressionKind
        switch current.kind {
        case .integer(let n): advance(); kind = .literal(.integer(n))
        case .string(let s): advance(); kind = .literal(.string(s))
        case .symbol(let s): advance(); kind = .literal(.symbol(s))
        case .identifier(let name): advance(); kind = .variable(name)
        case .binary("-"):
            advance()
            if current.kind == .minimumMagnitude { advance(); kind = .literal(.integer(.min)) }
            else if case .integer(let n) = current.kind { advance(); kind = .literal(.integer(-n)) }
            else { throw error("Nach - wird eine Ganzzahl erwartet.") }
        case .minimumMagnitude: throw error("Ganzzahl ist zu groß (64-Bit-Grenze).")
        case .leftParen:
            advance()
            let result = try expression()
            try expect(.rightParen)
            return result
        case .leftBracket:
            advance()
            var parameters: [String] = []
            while current.kind == .colon { advance(); parameters.append(try identifier()) }
            if !parameters.isEmpty { try expect(.bar) }
            try validateNames(parameters)
            // expression() accounts for parentheses; block bodies also need a nesting limit.
            nesting += 1
            guard nesting <= 128 else { throw error("Block ist zu tief verschachtelt.") }
            let result = try body(until: .rightBracket)
            nesting -= 1
            guard Set(parameters).isDisjoint(with: result.temporaries) else { throw error("Blockargument ist auch als lokale Variable deklariert.") }
            try expect(.rightBracket)
            kind = .block(parameters, result)
        case .arrayStart:
            advance(); kind = .literal(.array(try arrayElements()))
        default: throw error("Ausdruck erwartet.")
        }
        return try Expression(kind: kind, position: position)
    }

    private mutating func arrayElements() throws -> [Literal] {
        nesting += 1
        defer { nesting -= 1 }
        guard nesting <= 128 else { throw error("Array ist zu tief verschachtelt.") }
        var elements: [Literal] = []
        while current.kind != .rightParen {
            switch current.kind {
            case .integer(let n): elements.append(.integer(n)); advance()
            case .string(let s): elements.append(.string(s)); advance()
            case .symbol(let s), .identifier(let s), .keyword(let s): elements.append(.symbol(s)); advance()
            case .binary("-"):
                advance()
                if current.kind == .minimumMagnitude { elements.append(.integer(.min)); advance() }
                else if case .integer(let n) = current.kind { elements.append(.integer(-n)); advance() }
                else { throw error("Ganzzahl erwartet.") }
            case .leftParen, .arrayStart: advance(); elements.append(.array(try arrayElements()))
            default: throw error("Literal oder ) im Array erwartet.")
            }
        }
        advance()
        return elements
    }
}
