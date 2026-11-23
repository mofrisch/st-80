import Foundation

extension SmalltalkRuntime {
    static let primitiveDescriptions: [String: [String: String]] = [
        "Object": [
            "class": "Returns the receiver's class.", "yourself": "Returns the receiver.",
            "printString": "Returns a readable representation.", "=": "Compares values.", "==": "Compares identity. Strings are treated as values.",
            "~=": "Tests whether values differ.", "isNil": "Tests whether the receiver is nil.", "notNil": "Tests whether the receiver is non-nil.",
            "ifNil:": "Evaluates a block if the receiver is nil.", "ifNotNil:": "Evaluates a block if the receiver is non-nil.",
            "respondsTo:": "Tests whether the receiver understands a message.", "perform:": "Sends a message by selector.",
            "perform:with:": "Sends a message by selector with one argument.",
            "error:line:column:": "Reports an error at a source position.",
        ],
        "Class": [
            "new": "Creates an object and sends initialize.", "new:": "Creates an array of the specified size.",
            "name": "Returns the class name.", "superclass": "Returns the superclass.", "subclasses": "Returns the immediate subclasses.",
            "subclass:instanceVariableNames:": "Creates a subclass.",
            "subclass:instanceVariableNames:classVariableNames:poolDictionaries:category:": "Creates a subclass. Class variables and pools must be empty.",
            "compile:": "Compiles or replaces an instance method.",
            "compileClass:": "Compiles or replaces a class method.",
            "methodNames": "Returns selectors of methods defined on the class.",
            "methodSourceAt:": "Returns the stored source code for a method.",
            "classMethodNames": "Returns selectors of class methods defined on the class.",
            "classMethodSourceAt:": "Returns the stored source code for a class method.",
            "isPrimitiveAt:": "Tests whether the selector names a VM primitive.",
            "instanceVariableNamesText": "Returns the instance variable names."
        ],
        "Integer": [
            "+": "Addition.", "-": "Subtraction.", "*": "Multiplication.",
            "/": "Exact integer division. Fractions are not implemented.", "//": "Division rounded down.",
            "\\\\": "Remainder from division rounded down.", "<": "Less than.", ">": "Greater than.",
            "<=": "Less than or equal to.", ">=": "Greater than or equal to.",
            "negated": "Returns the negated value.", "abs": "Returns the absolute value.", "squared": "Returns the square.",
            "timesRepeat:": "Repeats a block.", "to:do:": "Iterates through the final value, inclusive.",
            "to:by:do:": "Iterates with the specified step size.",
        ],
        "Boolean": [
            "not": "Negation.", "ifTrue:": "Evaluates a block if the receiver is true.", "ifFalse:": "Evaluates a block if the receiver is false.",
            "ifTrue:ifFalse:": "Evaluates one of two blocks.", "ifFalse:ifTrue:": "Evaluates one of two blocks.",
            "and:": "Short-circuiting logical AND.", "or:": "Short-circuiting logical OR.",
        ],
        "String": [",": "Concatenates two strings.", "size": "Returns the number of Unicode characters.", "at:": "Returns the character at a one-based index.", "asString": "Returns the string.", "asSymbol": "Converts the string to a symbol.", "characters": "Returns an array of Unicode characters.",
            "includes:": "Tests whether a character or substring is present.", "isLetter": "Tests whether the string is one letter.",
            "isNumber": "Tests whether the string is one numeric character.", "isASCIIDigit": "Tests whether the string is one ASCII digit.",
            "isLowercase": "Tests whether the string is one lowercase character.", "isWhitespace": "Tests whether the string is one whitespace character.",
            "isLineBreak": "Tests whether the string is a line break.", "asIntegerOrNil": "Parses a 64-bit integer."],
        "Symbol": ["asString": "Returns the symbol name as a string."],
        "Array": ["size": "Returns the number of elements.", "at:": "Returns the element at a one-based index.", "at:put:": "Sets an element.", "do:": "Visits each element.", "collect:": "Transforms each element.", "select:": "Filters elements.", "isEmpty": "Tests whether the array is empty.", "includes:": "Tests whether the array contains an element.",
            "joinedStringFrom:to:": "Joins the strings in an index range."],
        "BlockClosure": ["value": "Evaluates the block.", "value:": "Evaluates the block with one argument.", "value:value:": "Evaluates the block with two arguments.", "whileTrue:": "Repeats while the block evaluates to true.", "whileFalse:": "Repeats while the block evaluates to false."],
        "Transcript": ["record:": "Records transcript output for the current evaluation."],
    ]

    func primitive(_ receiver: Value, _ selector: String, _ args: [Value]) throws -> Value? {
        switch selector {
        case "class": return .classObject(classOf(receiver))
        case "yourself": return receiver
        case "printString": return .string(printValue(receiver))
        case "=", "==": return .boolean(equal(receiver, args[0], identity: selector == "=="))
        case "~=": return .boolean(!equal(receiver, args[0]))
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
            case "includes:": return .boolean(array.elements.contains { equal($0, args[0]) })
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

    func subclass(of superclass: STClass, name: String, fields source: String) throws -> STClass {
        try validateSuperclass(superclass)
        guard name.first?.isUppercase == true && name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else {
            throw SmalltalkError("Class names must begin with an uppercase letter.")
        }
        guard globals[name] == nil else { throw SmalltalkError("\(name) already exists.") }
        guard classes.count < 128 else { throw SmalltalkError("A session can contain at most 128 classes.") }
        let fields = source.split(whereSeparator: \.isWhitespace).map(String.init)
        try validateFields(fields, inherited: superclass.fields)
        if recordingChanges {
            let escaped = source.replacingOccurrences(of: "'", with: "''")
            try journal.append(kind: .classDefinition, className: name, superclass: superclass.name, fields: fields, source: "\(superclass.name) subclass: #\(name) instanceVariableNames: '\(escaped)'")
        }
        let stClass = STClass(name, superclass: superclass, fields: fields)
        classes[name] = stClass
        catalogDirty = true
        globals[name] = .classObject(stClass)
        return stClass
    }

    func validateSuperclass(_ superclass: STClass) throws {
        guard superclass.name == "Object" || !Self.builtinNames.contains(superclass.name) else {
            throw SmalltalkError("Subclassing primitive classes is not implemented.")
        }
    }

    func validateFields(_ fields: [String], inherited: [String]) throws {
        guard CodeValidator.validNames(fields), Set(fields).isDisjoint(with: inherited), fields.count + inherited.count <= 64 else {
            throw SmalltalkError("Instance variable names must be valid and unique, with at most 64 variables.")
        }
    }

    static let builtinNames: Set<String> = ["Object", "Class", "UndefinedObject", "Boolean", "True", "False", "Number", "Integer", "SmallInteger", "String", "Symbol", "Array", "BlockClosure", "Transcript"]

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

    func integer(_ value: Value) throws -> Int64 {
        guard case .integer(let n) = value else { throw SmalltalkError("Expected an integer, got \(printValue(value)).") }
        return n
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

    func checked(_ result: (partialValue: Int64, overflow: Bool)) throws -> Int64 {
        guard !result.overflow else { throw SmalltalkError("64-bit integer overflow.") }
        return result.partialValue
    }

    func isNil(_ value: Value) -> Bool { if case .nilValue = value { return true }; return false }

    func equal(_ a: Value, _ b: Value, identity: Bool = false, depth: Int = 0) -> Bool {
        switch (a, b) {
        case (.integer(let a), .integer(let b)): return a == b
        case (.string(let a), .string(let b)), (.symbol(let a), .symbol(let b)): return a == b
        case (.boolean(let a), .boolean(let b)): return a == b
        case (.nilValue, .nilValue), (.transcript, .transcript): return true
        case (.object(let a), .object(let b)): return a === b
        case (.classObject(let a), .classObject(let b)): return a === b
        case (.block(let a), .block(let b)): return a === b
        case (.array(let a), .array(let b)):
            if a === b { return true }
            guard !identity, depth < 32, a.elements.count == b.elements.count else { return false }
            return zip(a.elements, b.elements).allSatisfy { equal($0, $1, depth: depth + 1) }
        default: return false
        }
    }

    func primitiveSelectors(_ stClass: STClass) -> Set<String> {
        let own = Set((Self.primitiveDescriptions[stClass.name] ?? [:]).keys)
        return own.union(stClass.superclass.map(primitiveSelectors) ?? [])
    }

    func reflectedMethods(on target: STClass, side: MethodSide) -> [MethodInfo] {
        var methods = target[side].map { MethodInfo(selector: $0.key, source: $0.value.source, isPrimitive: false) }
        if side == .instance {
            for (selector, description) in Self.primitiveDescriptions[target.name] ?? [:] where target.methods[selector] == nil {
                methods.append(MethodInfo(selector: selector, source: primitiveSource(selector, description), isPrimitive: true))
            }
        }
        return methods.sorted { $0.selector < $1.selector }
    }

    func reflectedMethodSource(_ selector: String, on target: STClass, side: MethodSide) -> String? {
        if let method = target[side][selector] { return method.source }
        guard side == .instance, let description = Self.primitiveDescriptions[target.name]?[selector] else { return nil }
        return primitiveSource(selector, description)
    }

    func isReflectedPrimitive(_ selector: String, on target: STClass, side: MethodSide) -> Bool {
        side == .instance && target.methods[selector] == nil && Self.primitiveDescriptions[target.name]?[selector] != nil
    }

    private func primitiveSource(_ selector: String, _ description: String) -> String {
        "\(selector)\n\n\"\(description)\"\n\n<primitive>"
    }

    func appendTranscript(_ text: String) throws {
        guard transcript.utf8.count + text.utf8.count <= 65_536 else { throw SmalltalkError("Transcript output is limited to 64 KiB per evaluation.") }
        transcript += text
    }
}
