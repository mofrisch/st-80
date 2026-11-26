import Foundation

extension SmalltalkRuntime {
    func integer(_ value: Value) throws -> Int64 {
        if case .largeInteger = value { throw SmalltalkError("Integer is outside the 64-bit range required here.") }
        guard case .integer(let n) = value else { throw SmalltalkError("Expected an integer, got \(printValue(value)).") }
        return n
    }

    func unboundedInteger(_ value: Value) throws -> BigInteger {
        switch value {
        case .integer(let n): return BigInteger(n)
        case .largeInteger(let n): return n
        default: throw SmalltalkError("Expected an integer, got \(printValue(value)).")
        }
    }

    func integerValue(_ integer: BigInteger) -> Value {
        integer.int64.map(Value.integer) ?? .largeInteger(integer)
    }

    func boolean(_ value: Value) throws -> Bool {
        guard case .boolean(let b) = value else { throw SmalltalkError("Expected true or false, got \(printValue(value)).") }
        return b
    }

    func string(_ value: Value) throws -> String {
        guard case .string(let s) = value else { throw SmalltalkError("Expected a string.") }
        return s
    }

    func symbol(_ value: Value) throws -> String {
        guard case .symbol(let s) = value else { throw SmalltalkError("Expected a symbol such as #Counter.") }
        return s
    }

    func index(_ value: Value, count: Int) throws -> Int {
        let number = try integer(value)
        guard number >= 1 && number <= count else { throw SmalltalkError("Index \(number) is outside the range 1…\(count).") }
        return Int(number - 1)
    }

    func sequenceElements(_ value: Value) throws -> [Value] {
        if case .array(let array) = value { return array.elements }
        return try withRoots([value]) { roots in
            let size = try integer(send(value, "size", []))
            guard (0...Int64(arrayLimit)).contains(size) else { throw SmalltalkError("Invalid argument collection size.") }
            var elements: [Value] = []
            elements.reserveCapacity(Int(size))
            for index in 0..<size {
                let element = try send(value, "at:", [.integer(index + 1)])
                roots.add(element)
                elements.append(element)
            }
            return elements
        }
    }

    func isNil(_ value: Value) -> Bool { if case .nilValue = value { return true }; return false }

    func equal(_ a: Value, _ b: Value, identity: Bool = false) throws -> Bool {
        struct ArrayPair: Hashable {
            let left: ObjectIdentifier
            let right: ObjectIdentifier
        }
        enum Comparison {
            case values(Value, Value)
            case elements(STArray, STArray, Int)
        }

        var pending: [Comparison] = [.values(a, b)]
        var compared: Set<ArrayPair> = []
        while let comparison = pending.popLast() {
            switch comparison {
            case .elements(let left, let right, let index):
                guard index < left.elements.count else { continue }
                // Keep one continuation per array rather than enqueueing every
                // element of a wide or deeply nested graph at once.
                pending.append(.elements(left, right, index + 1))
                pending.append(.values(left.elements[index], right.elements[index]))
            case .values(let left, let right):
                try tick()
                switch (left, right) {
                case (.integer(let a), .integer(let b)): if a != b { return false }
                case (.largeInteger(let a), .largeInteger(let b)):
                    try chargeNumericWork(max(a.wordCount, b.wordCount))
                    if a != b { return false }
                case (.fraction(let a), .fraction(let b)):
                    try chargeNumericWork(max(a.numerator.wordCount, b.numerator.wordCount) + max(a.denominator.wordCount, b.denominator.wordCount))
                    if a != b { return false }
                case (.integer(let a), .fraction(let b)), (.fraction(let b), .integer(let a)):
                    if identity || b.denominator != .one || b.numerator.int64 != a { return false }
                case (.largeInteger(let a), .fraction(let b)), (.fraction(let b), .largeInteger(let a)):
                    try chargeNumericWork(max(a.wordCount, b.numerator.wordCount))
                    if identity || b.denominator != .one || b.numerator != a { return false }
                case (.float(let a), .float(let b)): if a != b { return false }
                case (.integer(let a), .float(let b)), (.float(let b), .integer(let a)):
                    if identity || Int64(exactly: b) != a { return false }
                case (.largeInteger(let a), .float(let b)), (.float(let b), .largeInteger(let a)):
                    if identity || BigInteger(exactly: b) != a { return false }
                case (.fraction(let a), .float(let b)), (.float(let b), .fraction(let a)):
                    if identity || a.doubleValue != b { return false }
                case (.scaledDecimal(let decimal), let other), (let other, .scaledDecimal(let decimal)):
                    if try !equalScaledDecimal(decimal, other: other, identity: identity) { return false }
                case (.character(let a), .character(let b)): if a != b { return false }
                case (.string(let a), .string(let b)), (.symbol(let a), .symbol(let b)): if a != b { return false }
                case (.boolean(let a), .boolean(let b)): if a != b { return false }
                case (.nilValue, .nilValue), (.transcript, .transcript): break
                case (.object(let a), .object(let b)): if a !== b { return false }
                case (.classObject(let a), .classObject(let b)): if a !== b { return false }
                case (.block(let a), .block(let b)): if a !== b { return false }
                case (.array(let a), .array(let b)):
                    if a === b { continue }
                    guard !identity, a.elements.count == b.elements.count else { return false }
                    let pair = ArrayPair(left: ObjectIdentifier(a), right: ObjectIdentifier(b))
                    // Shared branches are compared once; revisiting a cycle
                    // does not make otherwise equal contents unequal.
                    if compared.insert(pair).inserted { pending.append(.elements(a, b, 0)) }
                default: return false
                }
            }
        }
        return true
    }
}
