import Darwin
import Foundation

extension SmalltalkRuntime {
    func primitive(_ receiver: Value, _ selector: String, _ args: [Value]) throws -> Value? {
        switch selector {
        case "basicNew:", "basicSize", "basicAt:", "basicAt:put:":
            return try indexedPrimitive(receiver, selector, args)
        case "class": return .classObject(classOf(receiver))
        case "copy": return try copyValue(receiver)
        case "hash", "identityHash": return .integer(try hashValue(receiver, identity: selector == "identityHash"))
        case "yourself": return receiver
        case "printString": return .string(printValue(receiver))
        case "=", "==": return .boolean(try equal(receiver, args[0], identity: selector == "==", dispatch: false))
        case "~~": return .boolean(try !equal(receiver, args[0], identity: true))
        case "~=": return .boolean(try !equal(receiver, args[0]))
        case "isNil": return .boolean(isNil(receiver))
        case "notNil": return .boolean(!isNil(receiver))
        case "ifNil:": return isNil(receiver) ? try invokeBlock(args[0]) : receiver
        case "ifNotNil:": return isNil(receiver) ? .nilValue : try invokeBlock(args[0])
        case "respondsTo:":
            let name = try symbol(args[0])
            return .boolean(try lookupMethod(name, on: receiver) != nil
                || hasReflectedPrimitive(name, on: receiver)
                || supportsIndexedOperation(name, on: receiver)
                || respondsToActiveExceptionControl(receiver, selector: name))
        case let name where Self.exceptionControlSelectors.contains(name):
            if let result = try exceptionControlPrimitive(receiver, selector, args) { return result }
        case "perform:": return try send(receiver, symbol(args[0]), [])
        case "perform:with:", "perform:with:with:", "perform:with:with:with:":
            return try send(receiver, symbol(args[0]), Array(args.dropFirst()))
        case "perform:withArguments:":
            return try send(receiver, symbol(args[0]), sequenceElements(args[1]))
        case "error:line:column:":
            throw SmalltalkError(try string(args[0]), at: SourcePosition(line: Int(try integer(args[1])), column: Int(try integer(args[2]))))
        case "/", "//", "\\\\":
            if receiver.isNumeric, args[0].isNumericZero {
                return try signalZeroDivide(dividend: receiver)
            }
        default: break
        }

        switch receiver {
        case .classObject(let stClass): return try classPrimitive(stClass, selector, args)
        case .integer(let n): return try integerPrimitive(n, selector, args) ?? integerProtocol(BigInteger(n), selector, args)
        case .largeInteger(let n): return try largeIntegerPrimitive(n, selector, args) ?? integerProtocol(n, selector, args)
        case .fraction(let n): return try fractionPrimitive(n, selector, args)
        case .scaledDecimal(let n): return try scaledDecimalPrimitive(n, selector, args)
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
            case "or:": return b ? .boolean(true) : .boolean(try boolean(evaluateValuable(args[0], as: "value")))
            case "&": return .boolean(try boolean(args[0]) && b)
            case "|": return .boolean(try boolean(args[0]) || b)
            case "eqv:": return .boolean(try boolean(args[0]) == b)
            case "xor:": return .boolean(try boolean(args[0]) != b)
            default: return nil
            }
        case .string(let string):
            return try stringPrimitive(receiver, contents: string, selector, args)
        case .symbol(let name):
            switch selector {
            case "asString": return .string(name)
            case "asSymbol": return receiver
            case "size", "at:", "do:", "asLowercase", "asUppercase", "sameAs:", "<", "<=", ">", ">=", "min:", "max:", "between:and:":
                return try stringPrimitive(receiver, contents: name, selector, args)
            default: return nil
            }
        case .array(let array):
            switch selector {
            case "size": return .integer(Int64(array.elements.count))
            case "isEmpty": return .boolean(array.elements.isEmpty)
            case "includes:":
                for index in array.elements.indices {
                    if try equal(array.elements[index], args[0]) { return .boolean(true) }
                }
                return .boolean(false)
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
                    for element in elements { _ = try evaluateValuable(args[0], as: "value:", [element]) }
                    return receiver
                case "collect:":
                    return try self.array(elements.map {
                        let result = try evaluateValuable(args[0], as: "value:", [$0])
                        evaluationRoots.append(result)
                        return result
                    })
                default:
                    return try self.array(elements.filter { try boolean(evaluateValuable(args[0], as: "value:", [$0])) })
                }
            default: return nil
            }
        case .block(let block):
            switch selector {
            case "value", "value:", "value:value:": return try invokeBlock(receiver, args)
            case "argumentCount": return .integer(Int64(block.parameters.count))
            case "valueWithArguments:": return try invokeBlock(receiver, sequenceElements(args[0]))
            case "on:do:": return try evaluateProtectedBlock(receiver, selector: args[0], action: args[1])
            case "ensure:", "ifCurtailed:":
                return try evaluateBlock(receiver, cleanup: args[0], always: selector == "ensure:")
            case "whileTrue", "whileFalse", "whileTrue:", "whileFalse:":
                let condition = selector == "whileTrue" || selector == "whileTrue:"
                while try boolean(invokeBlock(receiver)) == condition {
                    if let body = args.first { _ = try evaluateValuable(body, as: "value") }
                }
                return .nilValue
            default: return nil
            }
        case .transcript:
            switch selector {
            case "record:":
                try appendTranscript(string(args[0]))
                return receiver
            case "_nextPutAllBatch:": return try nextPutAllBatch(receiver, source: args[0])
            default: return nil
            }
        case .object(let object):
            if selector == "_coerceElement:", let interval = classes["Interval"], object.stClass.inherits(from: interval) {
                let element = args[0]
                guard element.isInteger else { return element }
                switch (object.fields["start"], object.fields["step"]) {
                case (.fraction?, _), (_, .fraction?):
                    return .fraction(try ExactFraction(unboundedInteger(element), .one, charge: chargeNumericWork))
                default: return element
                }
            }
            if selector == "_tryAddAll:", let ordered = classes["OrderedCollection"], object.stClass.inherits(from: ordered) {
                return .boolean(try appendOrderedCollectionBatch(object, source: args[0]))
            }
            if selector == "_spliceAt:remove:with:", let ordered = classes["OrderedCollection"], object.stClass.inherits(from: ordered) {
                guard case .array(let incoming) = args[2] else { throw SmalltalkError("Invalid collection storage.") }
                return try spliceCollectionStorage(object, first: integer(args[0]), removed: integer(args[1]), values: incoming.elements[...])
            }
            if selector == "_commitWrite:", let stream = classes["CollectionStream"], object.stClass.inherits(from: stream) {
                return try commitStreamWrite(object, incoming: args[0])
            }
            if selector == "_hasStockSliceMethods:", let stream = classes["CollectionStream"], object.stClass.inherits(from: stream) {
                return .boolean(hasStockSliceMethods(args[0]))
            }
            if selector == "_nextPutAllBatch:" {
                return try nextPutAllBatch(receiver, source: args[0])
            }
            if selector.hasPrefix("_"), let stream = classes["FileStream"], object.stClass.inherits(from: stream) {
                for name in ["FileStream", "ReadFileStream", "WriteFileStream"] {
                    if Self.primitiveDescriptions[name]?[selector] != nil,
                       let owner = classes[name], object.stClass.inherits(from: owner) {
                        return try fileStreamPrimitive(object, selector, args)
                    }
                }
            }
            if object.stClass === classes["String"], let contents = receiver.textContents {
                return try stringPrimitive(receiver, contents: contents, selector, args)
            }
            if object.stClass === classes["ToolServices"] { return try toolPrimitive(selector, args) }
            return try exceptionPrimitive(receiver, object, selector, args)
        default: return nil
        }
    }

    private func hasStockSliceMethods(_ backing: Value) -> Bool {
        let className = classOf(backing).name
        guard ["Array", "ByteArray", "Interval", "OrderedCollection", "SortedCollection", "String", "Symbol"].contains(className),
              let library = try? SystemLibrary.shared.get() else { return false }
        return ["select:", "copyFrom:to:", "copyReplaceFrom:to:with:"].allSatisfy { selector in
            if let (method, owner, side) = lookupMethod(selector, on: backing) {
                return library.sources[side][owner.name]?[selector] == method.source
            }
            return className == "Array" && selector == "select:"
        }
    }

    private func appendOrderedCollectionBatch(_ collection: STObject, source: Value) throws -> Bool {
        guard collection.stClass === classes["OrderedCollection"],
              let arrayClass = classes["Array"],
              arrayClass.lookup("do:") == nil,
              let library = try? SystemLibrary.shared.get(),
              case .integer(let tally)? = collection.fields["tally"],
              (0...Int64(arrayLimit)).contains(tally) else { return false }

        let receiver = Value.object(collection)
        let methods = library.sources[.instance]["OrderedCollection"] ?? [:]
        let appendMethods = ["add:", "addLast:", "add:beforeIndex:", "_checkInsertionIndex:", "_makeRoomFor:", "_reserve:"]
        let arrayFactory = Value.classObject(arrayClass)
        // A snapshot may replace the individual sends only with the stock traversal and append methods.
        guard appendMethods.allSatisfy({ selector in
            guard let shipped = methods[selector] else { return false }
            return lookupMethod(selector, on: receiver)?.0.source == shipped
        }), lookupMethod("_spliceAt:remove:with:", on: receiver) == nil,
            arrayClass.lookup("at:put:") == nil, arrayClass.lookup("yourself") == nil,
            lookupMethod("new:", on: arrayFactory) == nil,
            let shippedArrayWith = library.sources[.classSide]["Array"]?["with:"],
            lookupMethod("with:", on: arrayFactory)?.0.source == shippedArrayWith else { return false }

        let values: ArraySlice<Value>
        switch source {
        case .array(let incoming):
            values = incoming.elements[...]
        case .object(let incoming) where incoming.stClass === collection.stClass:
            guard let shippedDo = methods["do:"], let shippedAsArray = methods["asArray"],
                  lookupMethod("do:", on: source)?.0.source == shippedDo,
                  lookupMethod("asArray", on: source)?.0.source == shippedAsArray,
                  let shippedCopy = library.sources[.instance]["Array"]?["copyFrom:to:"],
                  arrayClass.lookup("copyFrom:to:")?.0.source == shippedCopy,
                  arrayClass.lookup("at:") == nil,
                  case .array(let storage)? = incoming.fields["storage"],
                  case .integer(let count)? = incoming.fields["tally"],
                  (0...Int64(storage.elements.count)).contains(count) else { return false }
            values = storage.elements.prefix(Int(count))
        case .object(let bytes) where bytes.stClass === classes["ByteArray"]:
            guard let shippedDo = library.sources[.instance]["ByteArray"]?["do:"],
                  lookupMethod("do:", on: source)?.0.source == shippedDo,
                  lookupMethod("ifNil:", on: .nilValue) == nil,
                  lookupMethod("ifNil:", on: .integer(0)) == nil,
                  case .array(let storage)? = bytes.fields["storage"] else { return false }
            try chargeNumericWork(storage.elements.count)
            values = storage.elements.map { isNil($0) ? .integer(0) : $0 }[...]
        default:
            let text: String?
            if case .symbol(let name) = source { text = name }
            else { text = source.textContents }
            guard let text, lookupMethod("do:", on: source) == nil else { return false }
            try chargeNumericWork(text.utf8.count)
            values = text.unicodeScalars.map { .character($0.value) }[...]
        }
        if values.isEmpty { return true }
        guard values.count <= arrayLimit - Int(tally) else { return false }
        _ = try send(receiver, "_makeRoomFor:", [.integer(Int64(values.count))])
        _ = try spliceCollectionStorage(collection, first: tally + 1, removed: 0, values: values)
        return true
    }

    private func spliceCollectionStorage(_ object: STObject, first: Int64, removed: Int64, values: ArraySlice<Value>) throws -> Value {
        guard case .array(let storage)? = object.fields["storage"],
              case .integer(let used)? = object.fields["tally"], (0...storage.elements.count).contains(Int(used)) else {
            throw SmalltalkError("Invalid collection storage.")
        }
        guard (1...used + 1).contains(first), (0...used - first + 1).contains(removed) else {
            throw SmalltalkError("Invalid collection splice range.")
        }
        let start = Int(first - 1)
        let tail = start + Int(removed)
        let shift = values.count - Int(removed)
        let previousCount = Int(used)
        let count = previousCount + shift
        guard count <= storage.elements.count else { throw SmalltalkError("Insufficient collection storage.") }

        // The contents and tally change together, after the execution budget has been checked.
        let moved = shift == 0 ? 0 : previousCount - tail
        try chargeNumericWork(moved + values.count + Int(removed))
        if shift > 0 {
            for index in (tail..<previousCount).reversed() { storage.elements[index + shift] = storage.elements[index] }
        } else if shift < 0 {
            for index in tail..<previousCount { storage.elements[index + shift] = storage.elements[index] }
            for index in count..<previousCount { storage.elements[index] = .nilValue }
        }
        for (offset, value) in values.enumerated() { storage.elements[start + offset] = value }
        object.fields["tally"] = .integer(Int64(count))
        return .object(object)
    }

    private func commitStreamWrite(_ object: STObject, incoming value: Value) throws -> Value {
        guard case .object(let buffer)? = object.fields["buffer"],
              case .integer(let used)? = buffer.fields["tally"], (0...Int64(arrayLimit)).contains(used),
              case .integer(let cursor)? = object.fields["cursor"], (0...used).contains(cursor),
              case .array(let incoming) = value else { throw SmalltalkError("Invalid stream storage.") }
        let count = Int64(incoming.elements.count)
        let overwritten = min(count, used - cursor)
        var newByteCount: Int64?
        if case .integer(let byteCount)? = object.fields["byteCount"] {
            let limit: Int64 = compilationMode ? 262_144 : 65_536
            guard (0...limit).contains(byteCount), case .array(let storage)? = buffer.fields["storage"],
                  used <= storage.elements.count else { throw SmalltalkError("Invalid text stream storage.") }
            let removedBytes = try streamTextBytes(storage.elements[Int(cursor)..<Int(cursor + overwritten)])
            let writtenBytes = try streamTextBytes(incoming.elements[...])
            let size = byteCount - removedBytes + writtenBytes
            guard (0...limit).contains(size) else { throw SmalltalkError("The text stream exceeds the string size limit.") }
            newByteCount = size
        }
        // Publish the new position only after the storage update. No evaluation
        // or budget check can interrupt these changes.
        _ = try spliceCollectionStorage(buffer, first: cursor + 1, removed: overwritten, values: incoming.elements[...])
        object.fields["cursor"] = .integer(cursor + count)
        if let newByteCount { object.fields["byteCount"] = .integer(newByteCount) }
        return .object(object)
    }

    private func streamTextBytes(_ values: ArraySlice<Value>) throws -> Int64 {
        var count: Int64 = 0
        for value in values {
            guard case .character(let codePoint) = value, let scalar = Unicode.Scalar(codePoint) else {
                throw SmalltalkError("A text stream expects characters.")
            }
            count += Int64(scalar.utf8.count)
        }
        return count
    }

    private func evaluateValuable(_ valuable: Value, as selector: String, _ arguments: [Value] = []) throws -> Value {
        if case .block = valuable { return try invokeBlock(valuable, arguments) }
        return try send(valuable, selector, arguments)
    }

    private func stringPrimitive(_ receiver: Value, contents string: String, _ selector: String, _ args: [Value]) throws -> Value? {
        switch selector {
        case ",":
            let result = string + (try readableString(args[0]))
            guard result.utf8.count <= (compilationMode ? 262_144 : 65_536) else {
                throw SmalltalkError(compilationMode ? "String exceeds the 256 KiB limit." : "String exceeds the 64 KiB limit.")
            }
            return compilationMode ? .string(result) : try newString(result)
        case "size": return .integer(Int64(string.unicodeScalars.count))
        case "at:":
            let scalars = string.unicodeScalars
            let index = try index(args[0], count: scalars.count)
            return .character(scalars[scalars.index(scalars.startIndex, offsetBy: index)].value)
        case "at:put:":
            guard case .object(let object) = receiver else { throw SmalltalkError("This string is read-only. Send copy to make it writable.") }
            guard case .character(let scalar) = args[1], let character = Unicode.Scalar(scalar) else {
                throw SmalltalkError("A string element must be a character.")
            }
            try chargeNumericWork(string.utf8.count / 32 + 1)
            var contents = string.unicodeScalars
            let offset = try index(args[0], count: contents.count)
            let start = contents.index(contents.startIndex, offsetBy: offset)
            contents.replaceSubrange(start..<contents.index(after: start), with: CollectionOfOne(character))
            try setString(object, contents: String(contents))
            return args[1]
        case "_hasPrimitiveAtPut": return .boolean(lookupMethod("at:put:", on: receiver) == nil)
        case "_replaceCharacters:":
            guard case .object(let object) = receiver else { throw SmalltalkError("This string is read-only. Send copy to make it writable.") }
            try setString(object, contents: stringFromCharacters(args[0]))
            return receiver
        case "do:":
            for scalar in string.unicodeScalars {
                _ = try evaluateValuable(args[0], as: "value:", [.character(scalar.value)])
            }
            return receiver
        case "asLowercase", "asUppercase":
            var result = String.UnicodeScalarView()
            for scalar in string.unicodeScalars {
                let original = String(scalar)
                let mapping = selector == "asLowercase" ? original.lowercased() : original.uppercased()
                let mapped = mapping.unicodeScalars
                result.append(mapped.count == 1 ? mapped.first! : scalar)
            }
            return try newString(String(result))
        case "sameAs:", "<", "<=", ">", ">=", "min:", "max:", "between:and:":
            let lower = try collate(string, with: args[0])
            switch selector {
            case "sameAs:": return .boolean(lower == .orderedSame)
            case "<": return .boolean(lower == .orderedAscending)
            case "<=": return .boolean(lower != .orderedDescending)
            case ">": return .boolean(lower == .orderedDescending)
            case ">=": return .boolean(lower != .orderedAscending)
            case "min:": return lower == .orderedAscending ? receiver : args[0]
            case "max:": return lower == .orderedDescending ? receiver : args[0]
            default:
                return .boolean(try lower != .orderedAscending && collate(string, with: args[1]) != .orderedDescending)
            }
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
            // The previous bundled scanner sent this from its compiler sandbox
            // while compiling the replacement scanner during bootstrap.
            if compilationMode, activations.last?.context.homeClass?.name == "STScanner",
               string == "+-*/\\~<>=@%,&?!|", let legacyCharacter = args[0].textContents {
                return .boolean(string.contains(legacyCharacter))
            }
            return .boolean(false)
        case "isLetter": return .boolean(string.count == 1 && string.first?.isLetter == true)
        case "isNumber": return .boolean(string.count == 1 && string.first?.isNumber == true)
        case "isASCIIDigit":
            return .boolean(string.count == 1 && string.first.map { $0.isASCII && $0.isNumber } == true)
        case "isLowercase": return .boolean(string.count == 1 && string.first?.isLowercase == true)
        case "isWhitespace": return .boolean(string.count == 1 && string.first?.isWhitespace == true)
        case "isLineBreak": return .boolean(string == "\n" || string == "\r" || string == "\r\n")
        case "asIntegerOrNil":
            if let small = Int64(string) { return .integer(small) }
            let signed = string.first == "-" || string.first == "+"
            let digits = signed ? String(string.dropFirst()) : string
            guard let magnitude = try BigInteger.parseMagnitude(digits, radix: 10, charge: chargeNumericWork) else { return .nilValue }
            return integerValue(string.first == "-" ? -magnitude : magnitude)
        case "parseFloatOrNil":
            let spelling = string.replacingOccurrences(of: "d", with: "e").replacingOccurrences(of: "q", with: "e")
            guard let number = Double(spelling), number.isFinite else { return .nilValue }
            return .float(number)
        case "parseScaledDecimalOrNil":
            return try scaledDecimalLiteral(string).map(Value.scaledDecimal) ?? .nilValue
        case "parseIntegerMagnitudeRadix:":
            let radix = try integer(args[0])
            guard (2...36).contains(radix), !string.isEmpty, string.utf8.allSatisfy({ byte in
                let digit = (48...57).contains(byte) ? Int(byte) - 48 : Int(byte) - 55
                return ((48...57).contains(byte) || (65...90).contains(byte)) && digit < radix
            }) else { return .nilValue }
            if let small = Int64(string, radix: Int(radix)) { return .integer(small) }
            guard let magnitude = try BigInteger.parseMagnitude(string, radix: Int(radix), charge: chargeNumericWork) else { return .nilValue }
            return integerValue(magnitude)
        default: return nil
        }
    }

    func readableString(_ value: Value) throws -> String {
        if case .symbol(let name) = value { return name }
        if let contents = value.textContents { return contents }
        let converted = try send(value, "asString", [])
        if case .symbol(let name) = converted { return name }
        return try stringFromCharacters(converted)
    }

    private func collate(_ string: String, with value: Value) throws -> ComparisonResult {
        let other = try readableString(value)
        try chargeNumericWork((string.utf8.count + other.utf8.count) / 32 + 1)
        let locale = Locale(identifier: "en_US_POSIX")
        let left = string.folding(options: .caseInsensitive, locale: locale)
        let right = other.folding(options: .caseInsensitive, locale: locale)
        if left == right { return .orderedSame }
        return left < right ? .orderedAscending : .orderedDescending
    }

    func newString(_ contents: String) throws -> Value {
        let string = try object(classes["String"]!)
        try setString(string, contents: contents)
        return .object(string)
    }

    private func setString(_ string: STObject, contents: String) throws {
        guard contents.utf8.count <= (compilationMode ? 262_144 : 65_536) else {
            throw SmalltalkError("The string representation is too long.")
        }
        string.fields["_contents"] = .string(contents)
    }

    private func stringFromCharacters(_ value: Value) throws -> String {
        if let contents = value.textContents { return contents }
        var scalars = String.UnicodeScalarView()
        var size = 0
        for element in try sequenceElements(value) {
            guard case .character(let codePoint) = element, let scalar = Unicode.Scalar(codePoint) else {
                throw SmalltalkError("A string element must be a character.")
            }
            size += scalar.utf8.count
            guard size <= (compilationMode ? 262_144 : 65_536) else {
                throw SmalltalkError("The string representation is too long.")
            }
            scalars.append(scalar)
        }
        return String(scalars)
    }

    private func characterPrimitive(_ codePoint: UInt32, _ selector: String) throws -> Value? {
        guard let scalar = Unicode.Scalar(codePoint) else { throw SmalltalkError("Invalid character code point.") }
        let character = Character(String(scalar))
        switch selector {
        case "codePoint", "hash", "identityHash": return .integer(Int64(codePoint))
        case "asString": return try newString(String(scalar))
        case "isLetter": return .boolean(character.isLetter)
        case "isDigit", "isAlphaNumeric":
            let isDigit = (0x30...0x39).contains(codePoint)
            return .boolean(isDigit || (selector == "isAlphaNumeric" && character.isLetter))
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
        case "_unixTime", "_clockResolution":
            guard let dateClass = classes["DateAndTime"], stClass.inherits(from: dateClass) else { return nil }
            var reading = timespec()
            let status = selector == "_unixTime" ? clock_gettime(CLOCK_REALTIME, &reading) : clock_getres(CLOCK_REALTIME, &reading)
            guard status == 0 else {
                return try send(.classObject(stClass), "error:", [.string("Could not read the system clock.")])
            }
            let nanosecondsPerSecond = BigInteger(1_000_000_000)
            let whole = try BigInteger(Int64(reading.tv_sec)).multiplied(by: nanosecondsPerSecond, charge: chargeNumericWork)
            return try fractionValue(whole + BigInteger(Int64(reading.tv_nsec)), nanosecondsPerSecond)
        case "_fractionNumerator:denominator:":
            guard stClass.name == "Fraction" else { return nil }
            let numerator = try unboundedInteger(args[0])
            let denominator = try unboundedInteger(args[1])
            if denominator.isZero { return try signalZeroDivide(dividend: args[0]) }
            return try fractionValue(numerator, denominator, factory: true)
        case "_stringWithAll:":
            guard stClass.name == "String" else { return nil }
            let elements = args[0]
            if lookupMethod("do:", on: elements) == nil {
                if case .array = elements { return try newString(stringFromCharacters(elements)) }
                if case .symbol(let name) = elements { return try newString(name) }
                if let text = elements.textContents { return try newString(text) }
            }
            let sequence = try send(.classObject(classes["Array"]!), "withAll:", [elements])
            return try newString(stringFromCharacters(sequence))
        case "name": return .symbol(stClass.name)
        case "superclass": return stClass.superclass.map(Value.classObject) ?? .nilValue
        case "subclasses", "allSubclasses":
            let root = stClass.instanceClass ?? stClass
            var subclasses = classes.values.filter { candidate in
                if selector == "subclasses" { return candidate.superclass === root }
                return candidate !== root && candidate.inherits(from: root)
            }
            if stClass.instanceClass != nil { subclasses = subclasses.map(\.metaclass) }
            return try array(subclasses.sorted { $0.name < $1.name }.map(Value.classObject))
        case "allSuperclasses":
            var superclasses: [Value] = []
            var parent = stClass.superclass
            while let ancestor = parent {
                superclasses.append(.classObject(ancestor))
                parent = ancestor.superclass
            }
            return try array(superclasses)
        case "instanceClass": return stClass.instanceClass.map(Value.classObject)
        case "instanceVariableNames:":
            guard let owner = stClass.instanceClass, let parent = owner.superclass else { return nil }
            let fields = try string(args[0]).split(whereSeparator: \.isWhitespace).map(String.init)
            try redefineClass(owner, superclass: parent, fields: owner.ownFields, classFields: fields)
            return .classObject(stClass)
        case "compile:":
            if let owner = stClass.instanceClass { return .symbol(try compile(string(args[0]), in: owner, side: .classSide)) }
            return .symbol(try compile(string(args[0]), in: stClass))
        case "compileClass:": return .symbol(try compile(string(args[0]), in: stClass, side: .classSide))
        case "methodNames": return try array(reflectedMethods(on: stClass, side: .instance).map { .string($0.selector) })
        case "classMethodNames": return try array(reflectedMethods(on: stClass, side: .classSide).map { .string($0.selector) })
        case "methodSourceAt:": return try reflectedMethodSource(string(args[0]), on: stClass, side: .instance).map(Value.string) ?? .nilValue
        case "classMethodSourceAt:": return try reflectedMethodSource(string(args[0]), on: stClass, side: .classSide).map(Value.string) ?? .nilValue
        case "isPrimitiveAt:": return try .boolean(isReflectedPrimitive(string(args[0]), on: stClass, side: .instance))
        case "instanceVariableNamesText": return .string(stClass.fields.isEmpty ? "None" : stClass.fields.joined(separator: " · "))
        case "subclass:instanceVariableNames:", "subclass:instanceVariableNames:classInstanceVariableNames:",
             "subclass:instanceVariableNames:classVariableNames:poolDictionaries:category:":
            let classFields = try args.count == 3 ? SmalltalkInterchange.names(in: string(args[2])) : []
            let classVariables = try args.count == 5 ? SmalltalkInterchange.names(in: string(args[2])) : []
            let pools = try args.count == 5 ? SmalltalkInterchange.names(in: string(args[3])) : []
            if args.count == 5 { _ = try string(args[4]) }
            let usesANSIAllocation = stClass === classes["Object"] || stClass.usesANSIAllocation
            return .classObject(try subclass(of: stClass, name: symbol(args[0]), fields: string(args[1]), classFields: classFields,
                                             classVariables: classVariables, pools: pools, usesANSIAllocation: usesANSIAllocation))
        case "new:":
            if stClass.indexedStorage != nil { return try indexedPrimitive(.classObject(stClass), "basicNew:", args) }
            guard stClass.name == "Array" || stClass.name == "String" else { throw SmalltalkError("This class does not support new:.") }
            let count = try integer(args[0])
            guard (0...Int64(arrayLimit)).contains(count) else { throw SmalltalkError("Array size must be between 0 and \(arrayLimit).") }
            if stClass.name == "String" { return try newString(String(repeating: " ", count: Int(count))) }
            return try array(Array(repeating: .nilValue, count: Int(count)))
        case "new":
            guard stClass.instanceClass == nil else { throw SmalltalkError("Each class has exactly one instance of its metaclass.") }
            if stClass.name == "Array" { return try array([]) }
            if stClass.name == "String" { return try newString("") }
            guard Self.heapBuiltinNames.contains(stClass.name) || !Self.builtinNames.contains(stClass.name) else {
                throw SmalltalkError("\(stClass.name) cannot be instantiated with new.")
            }
            let instance = Value.object(try object(stClass))
            if stClass === classes["Object"] { return instance }
            // A declarative class must not acquire a constructor just by naming
            // an instance method initialize. Legacy superclasses still set up their own state.
            if stClass.usesANSIAllocation {
                var ancestor = stClass.superclass
                while ancestor?.usesANSIAllocation == true { ancestor = ancestor?.superclass }
                if let ancestor, let (_, owner) = ancestor.lookup("initialize"), owner !== classes["Object"] {
                    _ = try send(instance, "initialize", [], startingAt: .instanceSuper(ancestor))
                }
                return instance
            }
            if lookupMethod("initialize", on: instance) != nil || stClass.inherits(from: classes["Object"]!) {
                return try withRoots([instance]) { _ in
                    _ = try send(instance, "initialize", [])
                    return instance
                }
            }
            return instance
        default: return nil
        }
    }

    func integerPrimitive(_ n: Int64, _ selector: String, _ args: [Value]) throws -> Value? {
        if let operand = args.first, Self.exactBinarySelectors.contains(selector) {
            switch operand {
            case .largeInteger, .fraction, .scaledDecimal, .float:
                return try largeIntegerPrimitive(BigInteger(n), selector, args)
            default: break
            }
        }
        switch selector {
        case "+", "-", "*":
            let operand = try integer(args[0])
            let result: (partialValue: Int64, overflow: Bool)
            switch selector {
            case "+": result = n.addingReportingOverflow(operand)
            case "-": result = n.subtractingReportingOverflow(operand)
            default: result = n.multipliedReportingOverflow(by: operand)
            }
            if result.overflow { return try largeIntegerPrimitive(BigInteger(n), selector, args) }
            return .integer(result.partialValue)
        case "/", "//", "\\\\":
            let divisor = try integer(args[0])
            guard divisor != 0 else { throw SmalltalkError("Division by zero.") }
            if n == .min && divisor == -1 { return try largeIntegerPrimitive(BigInteger(n), selector, args) }
            let quotient = n / divisor
            let remainder = n % divisor
            if selector == "/" {
                return remainder == 0 ? .integer(quotient) : try fractionValue(BigInteger(n), BigInteger(divisor))
            }
            let roundDown = remainder != 0 && (n < 0) != (divisor < 0)
            if selector == "//" { return .integer(roundDown ? quotient - 1 : quotient) }
            return .integer(roundDown ? remainder + divisor : remainder)
        case "<": return .boolean(n < (try integer(args[0])))
        case ">": return .boolean(n > (try integer(args[0])))
        case "<=": return .boolean(n <= (try integer(args[0])))
        case ">=": return .boolean(n >= (try integer(args[0])))
        case "negated", "abs":
            if n == .min { return integerValue(-BigInteger(n)) }
            return .integer(selector == "negated" ? -n : abs(n))
        case "squared":
            let squared = n.multipliedReportingOverflow(by: n)
            if squared.overflow { return try largeIntegerPrimitive(BigInteger(n), selector, args) }
            return .integer(squared.partialValue)
        case "numerator": return .integer(n)
        case "denominator": return .integer(1)
        case "asFloat", "asFloatE", "asFloatD", "asFloatQ": return .float(Double(n))
        case "asScaledDecimal:": return try convertToScaledDecimal(.integer(n), scale: args[0])
        case "asCharacter":
            guard let codePoint = UInt32(exactly: n), Unicode.Scalar(codePoint) != nil else {
                throw SmalltalkError("Invalid Unicode scalar code point.")
            }
            return .character(codePoint)
        case "timesRepeat:":
            if n > 0 { for _ in 0..<n { _ = try invokeBlock(args[0]) } }
            return .integer(n)
        case "to:do:", "to:by:do:":
            let hasStep = selector == "to:by:do:"
            let increment = hasStep ? args[1] : .integer(1)
            guard case .integer(let end) = args[0], case .integer(let step) = increment else {
                return try largeIntegerPrimitive(BigInteger(n), selector, args)
            }
            let block = args[hasStep ? 2 : 1]
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

    func appendTranscript(_ text: String) throws {
        guard transcript.utf8.count + text.utf8.count <= 65_536 else { throw SmalltalkError("Transcript output is limited to 64 KiB per evaluation.") }
        transcript += text
    }
}
