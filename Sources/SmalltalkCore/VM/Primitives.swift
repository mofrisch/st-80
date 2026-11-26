import Foundation

extension SmalltalkRuntime {
    func primitive(_ receiver: Value, _ selector: String, _ args: [Value]) throws -> Value? {
        switch selector {
        case "class": return .classObject(classOf(receiver))
        case "yourself": return receiver
        case "printString": return .string(printValue(receiver))
        case "=", "==": return .boolean(try equal(receiver, args[0], identity: selector == "=="))
        case "~~": return .boolean(try !equal(receiver, args[0], identity: true))
        case "~=": return .boolean(try !equal(receiver, args[0]))
        case "isNil": return .boolean(isNil(receiver))
        case "notNil": return .boolean(!isNil(receiver))
        case "ifNil:": return isNil(receiver) ? try invokeBlock(args[0]) : receiver
        case "ifNotNil:": return isNil(receiver) ? .nilValue : try invokeBlock(args[0])
        case "respondsTo:":
            let name = try symbol(args[0])
            return .boolean(lookupMethod(name, on: receiver) != nil || primitiveSelectors(classOf(receiver)).contains(name))
        case "perform:": return try send(receiver, symbol(args[0]), [])
        case "perform:with:", "perform:with:with:", "perform:with:with:with:":
            return try send(receiver, symbol(args[0]), Array(args.dropFirst()))
        case "perform:withArguments:":
            return try send(receiver, symbol(args[0]), sequenceElements(args[1]))
        case "error:line:column:":
            throw SmalltalkError(try string(args[0]), at: SourcePosition(line: Int(try integer(args[1])), column: Int(try integer(args[2]))))
        default: break
        }

        switch receiver {
        case .classObject(let stClass): return try classPrimitive(stClass, selector, args)
        case .integer(let n): return try integerPrimitive(n, selector, args)
        case .float(let number): return try floatPrimitive(number, selector, args)
        case .character(let codePoint): return try characterPrimitive(codePoint, selector)
        case .boolean(let b):
            switch selector {
            case "not": return .boolean(!b)
            case "ifTrue:": return b ? try invokeBlock(args[0]) : .nilValue
            case "ifFalse:": return b ? .nilValue : try invokeBlock(args[0])
            case "ifTrue:ifFalse:": return try invokeBlock(args[b ? 0 : 1])
            case "ifFalse:ifTrue:": return try invokeBlock(args[b ? 1 : 0])
            case "and:": return b ? .boolean(try boolean(invokeBlock(args[0]))) : .boolean(false)
            case "or:": return b ? .boolean(true) : .boolean(try boolean(invokeBlock(args[0])))
            case "&": return .boolean(try boolean(args[0]) && b)
            case "|": return .boolean(try boolean(args[0]) || b)
            case "eqv:": return .boolean(try boolean(args[0]) == b)
            case "xor:": return .boolean(try boolean(args[0]) != b)
            default: return nil
            }
        case .string(let string):
            switch selector {
            case ",":
                let result = string + (try self.string(args[0]))
                guard result.utf8.count <= (compilationMode ? 262_144 : 65_536) else {
                    throw SmalltalkError(compilationMode ? "String exceeds the 256 KiB limit." : "String exceeds the 64 KiB limit.")
                }
                return .string(result)
            case "size": return .integer(Int64(string.unicodeScalars.count))
            case "at:":
                let scalars = string.unicodeScalars
                let index = try index(args[0], count: scalars.count)
                return .character(scalars[scalars.index(scalars.startIndex, offsetBy: index)].value)
            case "asString": return receiver
            case "asSymbol": return .symbol(string)
            case "asCharacter":
                let scalars = string.unicodeScalars
                guard scalars.count == 1, let scalar = scalars.first else { throw SmalltalkError("Expected one Unicode scalar.") }
                return .character(scalar.value)
            case "utf8Size": return .integer(Int64(string.utf8.count))
            case "suffixFittingUTF8:":
                let budget = min(max(0, try integer(args[0])), 262_144)
                var count = 0
                var start = string.endIndex
                while start != string.startIndex {
                    let previous = string.index(before: start)
                    let bytes = string[previous..<start].utf8.count
                    guard count + bytes <= budget else { break }
                    count += bytes
                    start = previous
                }
                return .string(String(string[start...]))
            case "includesIgnoringCase:": return .boolean(string.localizedCaseInsensitiveContains(try self.string(args[0])))
            case "characters": return try array(string.map { .string(String($0)) })
            case "includes:":
                if case .character(let codePoint) = args[0] {
                    return .boolean(string.unicodeScalars.contains { $0.value == codePoint })
                }
                let substring = try self.string(args[0])
                return .boolean(string.contains(substring))
            case "isLetter": return .boolean(string.count == 1 && string.first?.isLetter == true)
            case "isNumber": return .boolean(string.count == 1 && string.first?.isNumber == true)
            case "isASCIIDigit":
                return .boolean(string.count == 1 && string.first.map { $0.isASCII && $0.isNumber } == true)
            case "isLowercase": return .boolean(string.count == 1 && string.first?.isLowercase == true)
            case "isWhitespace": return .boolean(string.count == 1 && string.first?.isWhitespace == true)
            case "isLineBreak": return .boolean(string == "\n" || string == "\r" || string == "\r\n")
            case "asIntegerOrNil": return Int64(string).map(Value.integer) ?? .nilValue
            case "parseFloatOrNil":
                let spelling = string.replacingOccurrences(of: "d", with: "e").replacingOccurrences(of: "q", with: "e")
                guard let number = Double(spelling), number.isFinite else { return .nilValue }
                return .float(number)
            case "parseIntegerMagnitudeRadix:":
                let radix = try integer(args[0])
                guard (2...36).contains(radix), !string.isEmpty, string.utf8.allSatisfy({ byte in
                    let digit = (48...57).contains(byte) ? Int(byte) - 48 : Int(byte) - 55
                    return ((48...57).contains(byte) || (65...90).contains(byte)) && digit < radix
                }) else { return .nilValue }
                guard let magnitude = UInt64(string, radix: Int(radix)) else { return .symbol("overflow") }
                if magnitude == UInt64(Int64.max) + 1 { return .symbol("minimumMagnitude") }
                return Int64(exactly: magnitude).map(Value.integer) ?? .symbol("overflow")
            default: return nil
            }
        case .symbol(let name): return selector == "asString" ? .string(name) : nil
        case .array(let array):
            switch selector {
            case "size": return .integer(Int64(array.elements.count))
            case "isEmpty": return .boolean(array.elements.isEmpty)
            case "includes:": return .boolean(try array.elements.contains { try equal($0, args[0]) })
            case "joinedStringFrom:to:":
                let first = try integer(args[0]), last = try integer(args[1])
                guard first >= 1, first <= array.elements.count + 1, last >= first - 1, last <= array.elements.count else {
                    throw SmalltalkError("Invalid array range.")
                }
                let limit = compilationMode ? 262_144 : 65_536
                var remaining = limit
                var result = ""
                for item in array.elements[Int(first - 1)..<Int(last)] {
                    let text = try string(item)
                    remaining -= text.utf8.count
                    guard remaining >= 0 else { throw SmalltalkError("The concatenated string is too long.") }
                    result += text
                }
                return .string(result)
            case "at:": return array.elements[try index(args[0], count: array.elements.count)]
            case "at:put:":
                array.elements[try index(args[0], count: array.elements.count)] = args[1]
                return args[1]
            case "do:", "collect:", "select:":
                let elements = array.elements
                let rootCount = evaluationRoots.count
                evaluationRoots.append(contentsOf: elements)
                defer { evaluationRoots.removeSubrange(rootCount...) }
                switch selector {
                case "do:":
                    for element in elements { _ = try invokeBlock(args[0], [element]) }
                    return receiver
                case "collect:":
                    return try self.array(elements.map {
                        let result = try invokeBlock(args[0], [$0])
                        evaluationRoots.append(result)
                        return result
                    })
                default:
                    return try self.array(elements.filter { try boolean(invokeBlock(args[0], [$0])) })
                }
            default: return nil
            }
        case .block(let block):
            switch selector {
            case "value", "value:", "value:value:": return try invokeBlock(receiver, args)
            case "argumentCount": return .integer(Int64(block.parameters.count))
            case "valueWithArguments:": return try invokeBlock(receiver, sequenceElements(args[0]))
            case "ensure:", "ifCurtailed:":
                let result: Value
                do {
                    result = try invokeBlock(receiver)
                } catch {
                    let returnValues = (error as? ReturnSignal).map { [$0.value] } ?? []
                    try withRoots(returnValues) { _ in _ = try invokeBlock(args[0]) }
                    throw error
                }
                return try withRoots([result]) { _ in
                    if selector == "ensure:" { _ = try invokeBlock(args[0]) }
                    return result
                }
            case "whileTrue", "whileFalse", "whileTrue:", "whileFalse:":
                let condition = selector == "whileTrue" || selector == "whileTrue:"
                while try boolean(invokeBlock(receiver)) == condition {
                    if let body = args.first { _ = try invokeBlock(body) }
                }
                return .nilValue
            default: return nil
            }
        case .transcript:
            guard selector == "record:" else { return nil }
            try appendTranscript(string(args[0]))
            return receiver
        case .object(let object):
            return object.stClass === classes["ToolServices"] ? try toolPrimitive(selector, args) : nil
        default: return nil
        }
    }

    private func characterPrimitive(_ codePoint: UInt32, _ selector: String) throws -> Value? {
        guard let scalar = Unicode.Scalar(codePoint) else { throw SmalltalkError("Invalid character code point.") }
        let character = Character(String(scalar))
        switch selector {
        case "codePoint", "hash", "identityHash": return .integer(Int64(codePoint))
        case "asString": return .string(String(scalar))
        case "isLetter": return .boolean(character.isLetter)
        case "isDigit": return .boolean(scalar.properties.numericType == .decimal)
        case "isAlphaNumeric": return .boolean(character.isLetter || scalar.properties.numericType == .decimal)
        case "isLowercase": return .boolean(character.isLowercase)
        case "isUppercase": return .boolean(character.isUppercase)
        case "asLowercase", "asUppercase":
            let mapping = selector == "asLowercase" ? character.lowercased() : character.uppercased()
            let scalars = mapping.unicodeScalars
            guard scalars.count == 1, let mapped = scalars.first else { return .character(codePoint) }
            return .character(mapped.value)
        default: return nil
        }
    }

    func classPrimitive(_ stClass: STClass, _ selector: String, _ args: [Value]) throws -> Value? {
        switch selector {
        case "name": return .symbol(stClass.name)
        case "superclass": return stClass.superclass.map(Value.classObject) ?? .nilValue
        case "subclasses": return try array(classes.values.filter { $0.superclass === stClass }.sorted { $0.name < $1.name }.map(Value.classObject))
        case "compile:": return .symbol(try compile(string(args[0]), in: stClass))
        case "compileClass:": return .symbol(try compile(string(args[0]), in: stClass, side: .classSide))
        case "methodNames": return try array(reflectedMethods(on: stClass, side: .instance).map { .string($0.selector) })
        case "classMethodNames": return try array(reflectedMethods(on: stClass, side: .classSide).map { .string($0.selector) })
        case "methodSourceAt:": return try reflectedMethodSource(string(args[0]), on: stClass, side: .instance).map(Value.string) ?? .nilValue
        case "classMethodSourceAt:": return try reflectedMethodSource(string(args[0]), on: stClass, side: .classSide).map(Value.string) ?? .nilValue
        case "isPrimitiveAt:": return try .boolean(isReflectedPrimitive(string(args[0]), on: stClass, side: .instance))
        case "instanceVariableNamesText": return .string(stClass.fields.isEmpty ? "None" : stClass.fields.joined(separator: " · "))
        case "subclass:instanceVariableNames:", "subclass:instanceVariableNames:classVariableNames:poolDictionaries:category:":
            if args.count == 5 {
                guard try string(args[2]).isEmpty && string(args[3]).isEmpty else { throw SmalltalkError("Class variables and pool dictionaries are not implemented.") }
                _ = try string(args[4])
            }
            return .classObject(try subclass(of: stClass, name: symbol(args[0]), fields: string(args[1])))
        case "new:":
            guard stClass.name == "Array" else { throw SmalltalkError("Only Array supports new:.") }
            let count = try integer(args[0])
            guard (0...Int64(arrayLimit)).contains(count) else { throw SmalltalkError("Array size must be between 0 and \(arrayLimit).") }
            return try array(Array(repeating: .nilValue, count: Int(count)))
        case "new":
            if stClass.name == "Array" { return try array([]) }
            if stClass.name == "String" { return .string("") }
            guard stClass.name == "Object" || Self.primitiveDescriptions[stClass.name] == nil && !["True", "False", "SmallInteger", "Number", "UndefinedObject"].contains(stClass.name) else {
                throw SmalltalkError("\(stClass.name) cannot be instantiated with new.")
            }
            let object = try object(stClass)
            let instance = Value.object(object)
            _ = try send(instance, "initialize", [])
            return instance
        default: return nil
        }
    }

    func integerPrimitive(_ n: Int64, _ selector: String, _ args: [Value]) throws -> Value? {
        if case .float? = args.first, ["+", "-", "*", "/", "//", "\\\\", "<", ">", "<=", ">="].contains(selector) {
            return try floatPrimitive(Double(n), selector, args)
        }
        switch selector {
        case "+": return .integer(try checked(n.addingReportingOverflow(integer(args[0]))))
        case "-": return .integer(try checked(n.subtractingReportingOverflow(integer(args[0]))))
        case "*": return .integer(try checked(n.multipliedReportingOverflow(by: integer(args[0]))))
        case "/", "//", "\\\\":
            let divisor = try integer(args[0])
            guard divisor != 0 else { throw SmalltalkError("Division by zero.") }
            guard !(n == .min && divisor == -1) else { throw SmalltalkError("64-bit integer overflow.") }
            let quotient = n / divisor
            let remainder = n % divisor
            if selector == "/" {
                guard remainder == 0 else { throw SmalltalkError("Fractions are not implemented. Use // for integer division.") }
                return .integer(quotient)
            }
            let roundDown = remainder != 0 && (n < 0) != (divisor < 0)
            if selector == "//" { return .integer(roundDown ? quotient - 1 : quotient) }
            return .integer(roundDown ? remainder + divisor : remainder)
        case "<": return .boolean(n < (try integer(args[0])))
        case ">": return .boolean(n > (try integer(args[0])))
        case "<=": return .boolean(n <= (try integer(args[0])))
        case ">=": return .boolean(n >= (try integer(args[0])))
        case "negated": return .integer(try checked(Int64(0).subtractingReportingOverflow(n)))
        case "abs": return .integer(n < 0 ? try checked(Int64(0).subtractingReportingOverflow(n)) : n)
        case "squared": return .integer(try checked(n.multipliedReportingOverflow(by: n)))
        case "asFloat", "asFloatE", "asFloatD", "asFloatQ": return .float(Double(n))
        case "asCharacter":
            guard let codePoint = UInt32(exactly: n), Unicode.Scalar(codePoint) != nil else {
                throw SmalltalkError("Invalid Unicode scalar code point.")
            }
            return .character(codePoint)
        case "timesRepeat:":
            if n > 0 { for _ in 0..<n { _ = try invokeBlock(args[0]) } }
            return .integer(n)
        case "to:do:", "to:by:do:":
            let end = try integer(args[0])
            let step: Int64 = selector == "to:do:" ? 1 : try integer(args[1])
            let block = args[selector == "to:do:" ? 1 : 2]
            guard step != 0 else { throw SmalltalkError("The step size must be nonzero.") }
            var current = n
            while step > 0 ? current <= end : current >= end {
                _ = try invokeBlock(block, [.integer(current)])
                let (next, overflow) = current.addingReportingOverflow(step)
                if overflow { break }
                current = next
            }
            return .integer(n)
        default: return nil
        }
    }

    private func checked(_ result: (partialValue: Int64, overflow: Bool)) throws -> Int64 {
        guard !result.overflow else { throw SmalltalkError("64-bit integer overflow.") }
        return result.partialValue
    }

    func appendTranscript(_ text: String) throws {
        guard transcript.utf8.count + text.utf8.count <= 65_536 else { throw SmalltalkError("Transcript output is limited to 64 KiB per evaluation.") }
        transcript += text
    }
}
