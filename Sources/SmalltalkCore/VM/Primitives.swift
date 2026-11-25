import Foundation

extension SmalltalkRuntime {
    func primitive(_ receiver: Value, _ selector: String, _ args: [Value]) throws -> Value? {
        switch selector {
        case "class": return .classObject(classOf(receiver))
        case "yourself": return receiver
        case "printString": return .string(printValue(receiver))
        case "=", "==": return .boolean(try equal(receiver, args[0], identity: selector == "=="))
        case "~=": return .boolean(try !equal(receiver, args[0]))
        case "isNil": return .boolean(isNil(receiver))
        case "notNil": return .boolean(!isNil(receiver))
        case "ifNil:": return isNil(receiver) ? try invokeBlock(args[0]) : receiver
        case "ifNotNil:": return isNil(receiver) ? .nilValue : try invokeBlock(args[0])
        case "respondsTo:":
            let name = try symbol(args[0])
            return .boolean(lookupMethod(name, on: receiver) != nil || primitiveSelectors(classOf(receiver)).contains(name))
        case "perform:": return try send(receiver, symbol(args[0]), [])
        case "perform:with:": return try send(receiver, symbol(args[0]), [args[1]])
        case "error:line:column:":
            throw SmalltalkError(try string(args[0]), at: SourcePosition(line: Int(try integer(args[1])), column: Int(try integer(args[2]))))
        default: break
        }

        switch receiver {
        case .classObject(let stClass): return try classPrimitive(stClass, selector, args)
        case .integer(let n): return try integerPrimitive(n, selector, args)
        case .boolean(let b):
            switch selector {
            case "not": return .boolean(!b)
            case "ifTrue:": return b ? try invokeBlock(args[0]) : .nilValue
            case "ifFalse:": return b ? .nilValue : try invokeBlock(args[0])
            case "ifTrue:ifFalse:": return try invokeBlock(args[b ? 0 : 1])
            case "ifFalse:ifTrue:": return try invokeBlock(args[b ? 1 : 0])
            case "and:": return b ? .boolean(try boolean(invokeBlock(args[0]))) : .boolean(false)
            case "or:": return b ? .boolean(true) : .boolean(try boolean(invokeBlock(args[0])))
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
            case "size": return .integer(Int64(string.count))
            case "at:":
                let index = try index(args[0], count: string.count)
                return .string(String(string[string.index(string.startIndex, offsetBy: index)]))
            case "asString": return receiver
            case "asSymbol": return .symbol(string)
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
        case .block:
            switch selector {
            case "value", "value:", "value:value:": return try invokeBlock(receiver, args)
            case "whileTrue:", "whileFalse:":
                while try boolean(invokeBlock(receiver)) == (selector == "whileTrue:") {
                    _ = try invokeBlock(args[0])
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
            return try send(.object(object), "initialize", [])
        default: return nil
        }
    }

    func integerPrimitive(_ n: Int64, _ selector: String, _ args: [Value]) throws -> Value? {
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
