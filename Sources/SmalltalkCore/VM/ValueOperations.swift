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
        guard let s = value.textContents else { throw SmalltalkError("Expected a string.") }
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
        if let string = value.textContents {
            try chargeNumericWork(string.utf8.count)
            return string.unicodeScalars.map { .character($0.value) }
        }
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

    func copyValue(_ value: Value) throws -> Value {
        switch value {
        case .string(let text):
            return try newString(text)
        case .object(let original):
            let copy = try object(original.stClass)
            copy.fields = original.fields
            return .object(copy)
        case .array(let original):
            return try array(original.elements)
        default:
            return value
        }
    }

    func hashValue(_ value: Value, identity: Bool) throws -> Int64 {
        var hash = Hasher()
        switch value {
        case .integer, .largeInteger, .fraction, .scaledDecimal, .float:
            // Mixed equality uses both exact comparisons and rounded binary64
            // comparisons. Every representation must agree when either does.
            hash.combine("Number")
        case .character(let scalar):
            return Int64(scalar)
        case .string(let string), .symbol(let string):
            try chargeNumericWork(string.utf8.count / 32 + 1)
            hash.combine(string)
        case .boolean(let boolean):
            hash.combine(boolean)
        case .nilValue:
            hash.combine("nil")
        case .transcript:
            hash.combine("Transcript")
        case .object(let object):
            if !identity, let string = value.textContents {
                try chargeNumericWork(string.utf8.count / 32 + 1)
                hash.combine(string)
            } else if !identity, let sequence = classes["SequenceableCollection"], object.stClass.inherits(from: sequence) {
                // Only class and size participate, so cycles never need recursive hashing.
                let count = try unboundedInteger(send(value, "size", []))
                hash.combine(ObjectIdentifier(object.stClass))
                hash.combine(count.int64)
            } else {
                hash.combine(ObjectIdentifier(object))
            }
        case .classObject(let stClass):
            hash.combine(ObjectIdentifier(stClass))
        case .block(let block):
            hash.combine(ObjectIdentifier(block))
        case .array(let array):
            // Cyclic arrays compare structurally. Size is invariant under that comparison.
            if identity { hash.combine(ObjectIdentifier(array)) }
            else { hash.combine(array.elements.count) }
        }
        return Int64(hash.finalize())
    }

    private func equalCharacters(_ a: String, _ b: String) throws -> Bool {
        let size = a.utf8.count
        guard size == b.utf8.count else { return false }
        // A message already pays for a short comparison.
        if size > 16 { try chargeNumericWork(size - 16) }
        return a.utf8.elementsEqual(b.utf8)
    }

    func equal(_ a: Value, _ b: Value, identity: Bool = false, dispatch: Bool = true) throws -> Bool {
        struct SequencePair: Hashable {
            let left: ObjectIdentifier
            let right: ObjectIdentifier
        }
        enum Comparison {
            case values(Value, Value, dispatch: Bool)
            case arrays(STArray, STArray, index: Int)
            case indexed(Value, Value, index: BigInteger, count: BigInteger)
        }

        let selector = identity ? "==" : "="
        let sequenceClass = classes["SequenceableCollection"]
        return try withRoots { roots in
            var pending: [Comparison] = [.values(a, b, dispatch: dispatch)]
            // Compare each pair once, including pairs discovered through a cycle
            // or multiple paths to a shared child.
            var compared: Set<SequencePair> = []
            while let comparison = pending.popLast() {
                switch comparison {
                case .arrays(let left, let right, let index):
                    guard index < left.elements.count else { continue }
                    pending.append(.arrays(left, right, index: index + 1))
                    pending.append(.values(left.elements[index], right.elements[index], dispatch: true))
                case .indexed(let left, let right, let index, let count):
                    guard index <= count else { continue }
                    let arguments = [integerValue(index)]
                    let lhs = try send(left, "at:", arguments)
                    let rhs = try withRoots([lhs]) { _ in try send(right, "at:", arguments) }
                    pending.append(.indexed(left, right, index: index + .one, count: count))
                    pending.append(.values(lhs, rhs, dispatch: true))
                case .values(let left, let right, let dispatch):
                    try tick()
                    if dispatch, lookupMethod(selector, on: left) != nil {
                        guard try boolean(send(left, selector, [right])) else { return false }
                        continue
                    }
                    if !identity, let a = left.textContents, let b = right.textContents {
                        guard try equalCharacters(a, b) else { return false }
                        continue
                    }
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
                    case (.string(let a), .string(let b)), (.symbol(let a), .symbol(let b)):
                        if try !equalCharacters(a, b) { return false }
                    case (.boolean(let a), .boolean(let b)): if a != b { return false }
                    case (.nilValue, .nilValue), (.transcript, .transcript): break
                    case (.classObject(let a), .classObject(let b)): if a !== b { return false }
                    case (.block(let a), .block(let b)): if a !== b { return false }
                    case (.array(let a), .array(let b)):
                        if a === b { continue }
                        guard !identity, a.elements.count == b.elements.count else { return false }
                        let pair = SequencePair(left: ObjectIdentifier(a), right: ObjectIdentifier(b))
                        if compared.insert(pair).inserted {
                            roots.add(left)
                            roots.add(right)
                            pending.append(.arrays(a, b, index: 0))
                        }
                    case (.object(let a), .object(let b)):
                        if a === b { continue }
                        guard !identity, a.stClass === b.stClass,
                              let sequenceClass, a.stClass.inherits(from: sequenceClass) else { return false }
                        let pair = SequencePair(left: ObjectIdentifier(a), right: ObjectIdentifier(b))
                        if compared.insert(pair).inserted {
                            roots.add(left)
                            roots.add(right)
                            let count = try unboundedInteger(send(left, "size", []))
                            let otherCount = try unboundedInteger(send(right, "size", []))
                            try chargeNumericWork(max(count.wordCount, otherCount.wordCount))
                            guard count == otherCount else { return false }
                            pending.append(.indexed(left, right, index: .one, count: count))
                        }
                    default: return false
                    }
                }
            }
            return true
        }
    }
}

extension Value {
    var isNumeric: Bool {
        switch self {
        case .integer, .largeInteger, .fraction, .scaledDecimal, .float: return true
        default: return false
        }
    }

    var isNumericZero: Bool {
        switch self {
        case .integer(let value): return value == 0
        case .largeInteger(let value): return value.isZero
        case .fraction(let value): return value.numerator.isZero
        case .scaledDecimal(let value): return value.coefficient.isZero
        case .float(let value): return value == 0
        default: return false
        }
    }

    var textContents: String? {
        switch self {
        case .string(let string): return string
        case .object(let object) where object.stClass.name == "String":
            if case .string(let string)? = object.fields["_contents"] { return string }
            return nil
        default: return nil
        }
    }
}
