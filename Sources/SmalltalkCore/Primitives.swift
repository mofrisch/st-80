import Foundation

extension SmalltalkRuntime {
    static let primitiveDescriptions: [String: [String: String]] = [
        "Object": [
            "class": "Klasse des Empfängers.", "yourself": "Gibt den Empfänger zurück.",
            "printString": "Lesbare Darstellung.", "=": "Vergleicht Werte.", "==": "Vergleicht Identität; Strings sind hier Werte.",
            "~=": "Ungleichheit.", "isNil": "Prüft auf nil.", "notNil": "Prüft auf einen Wert.",
            "ifNil:": "Wertet bei nil einen Block aus.", "ifNotNil:": "Wertet bei einem Wert einen Block aus.",
            "respondsTo:": "Prüft, ob eine Nachricht verstanden wird.", "perform:": "Sendet einen Selektor.",
            "perform:with:": "Sendet einen Selektor mit einem Argument.",
        ],
        "Class": [
            "new": "Erzeugt ein Objekt und sendet initialize.", "new:": "Erzeugt ein Array mit angegebener Größe.",
            "name": "Klassenname.", "superclass": "Oberklasse.", "subclasses": "Direkte Unterklassen.",
            "subclass:instanceVariableNames:": "Legt eine Unterklasse an.",
            "subclass:instanceVariableNames:classVariableNames:poolDictionaries:category:": "Legt eine Unterklasse an; Klassenvariablen und Pools müssen leer sein.",
            "compile:": "Kompiliert oder ersetzt eine Instanzmethode.",
        ],
        "Integer": [
            "+": "Addition.", "-": "Subtraktion.", "*": "Multiplikation.",
            "/": "Exakte Ganzzahldivision; Brüche sind noch nicht implementiert.", "//": "Abrundende Division.",
            "\\\\": "Rest zur abrundenden Division.", "<": "Kleiner als.", ">": "Größer als.",
            "<=": "Kleiner oder gleich.", ">=": "Größer oder gleich.",
            "negated": "Negierter Wert.", "abs": "Betrag.", "squared": "Quadrat.",
            "timesRepeat:": "Wiederholt einen Block.", "to:do:": "Iteriert einschließlich Endwert.",
            "to:by:do:": "Iteriert mit angegebener Schrittweite.",
        ],
        "Boolean": [
            "not": "Negation.", "ifTrue:": "Wertet bei true einen Block aus.", "ifFalse:": "Wertet bei false einen Block aus.",
            "ifTrue:ifFalse:": "Wählt einen von zwei Blöcken.", "ifFalse:ifTrue:": "Wählt einen von zwei Blöcken.",
            "and:": "Kurzschließendes Und.", "or:": "Kurzschließendes Oder.",
        ],
        "String": [",": "Verkettet zwei Strings.", "size": "Anzahl der Unicode-Zeichen.", "at:": "Zeichen an einer Position, ab 1.", "asString": "Gibt den String zurück.", "asSymbol": "Wandelt in ein Symbol um."],
        "Symbol": ["asString": "Symbolname als String."],
        "Array": ["size": "Anzahl der Elemente.", "at:": "Liest ein Element, ab Position 1.", "at:put:": "Schreibt ein Element.", "do:": "Besucht jedes Element.", "collect:": "Transformiert jedes Element.", "select:": "Filtert Elemente.", "isEmpty": "Prüft auf ein leeres Array."],
        "BlockClosure": ["value": "Wertet den Block aus.", "value:": "Wertet mit einem Argument aus.", "value:value:": "Wertet mit zwei Argumenten aus.", "whileTrue:": "Wiederholt, solange der Block true ergibt.", "whileFalse:": "Wiederholt, solange der Block false ergibt."],
        "Transcript": ["show:": "Schreibt Text ins Transcript.", "cr": "Schreibt einen Zeilenumbruch."],
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
            return .boolean(classOf(receiver).lookup(name) != nil || primitiveSelectors(classOf(receiver)).contains(name))
        case "perform:": return try send(receiver, symbol(args[0]), [])
        case "perform:with:": return try send(receiver, symbol(args[0]), [args[1]])
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
                guard result.utf8.count <= 65_536 else { throw SmalltalkError("String ist zu lang (maximal 64 KiB).") }
                return .string(result)
            case "size": return .integer(Int64(string.count))
            case "at:":
                let index = try index(args[0], count: string.count)
                return .string(String(string[string.index(string.startIndex, offsetBy: index)]))
            case "asString": return receiver
            case "asSymbol": return .symbol(string)
            default: return nil
            }
        case .symbol(let name): return selector == "asString" ? .string(name) : nil
        case .array(let array):
            switch selector {
            case "size": return .integer(Int64(array.elements.count))
            case "isEmpty": return .boolean(array.elements.isEmpty)
            case "at:": return array.elements[try index(args[0], count: array.elements.count)]
            case "at:put:":
                array.elements[try index(args[0], count: array.elements.count)] = args[1]
                return args[1]
            case "do:":
                for element in array.elements { _ = try invokeBlock(args[0], [element]) }
                return receiver
            case "collect:": return try self.array(array.elements.map { try invokeBlock(args[0], [$0]) })
            case "select:": return try self.array(array.elements.filter { try boolean(invokeBlock(args[0], [$0])) })
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
            switch selector {
            case "show:":
                let text: String
                if case .string(let string) = args[0] { text = string }
                else { text = try string(send(args[0], "printString", [])) }
                try appendTranscript(text)
                return receiver
            case "cr": try appendTranscript("\n"); return receiver
            default: return nil
            }
        default: return nil
        }
    }

    func classPrimitive(_ stClass: STClass, _ selector: String, _ args: [Value]) throws -> Value? {
        switch selector {
        case "name": return .symbol(stClass.name)
        case "superclass": return stClass.superclass.map(Value.classObject) ?? .nilValue
        case "subclasses": return try array(classes.values.filter { $0.superclass === stClass }.sorted { $0.name < $1.name }.map(Value.classObject))
        case "compile:": return .symbol(try compile(string(args[0]), in: stClass))
        case "subclass:instanceVariableNames:", "subclass:instanceVariableNames:classVariableNames:poolDictionaries:category:":
            if args.count == 5 {
                guard try string(args[2]).isEmpty && string(args[3]).isEmpty else { throw SmalltalkError("Klassenvariablen und Pool-Dictionaries sind noch nicht implementiert.") }
                _ = try string(args[4])
            }
            return .classObject(try subclass(of: stClass, name: symbol(args[0]), fields: string(args[1])))
        case "new:":
            guard stClass.name == "Array" else { throw SmalltalkError("new: wird hier nur von Array unterstützt.") }
            let count = try integer(args[0])
            guard (0...4_096).contains(count) else { throw SmalltalkError("Arraygröße muss zwischen 0 und 4.096 liegen.") }
            return try array(Array(repeating: .nilValue, count: Int(count)))
        case "new":
            if stClass.name == "Array" { return try array([]) }
            if stClass.name == "String" { return .string("") }
            guard stClass.name == "Object" || Self.primitiveDescriptions[stClass.name] == nil && !["True", "False", "SmallInteger", "Number", "UndefinedObject"].contains(stClass.name) else {
                throw SmalltalkError("\(stClass.name) kann nicht mit new erzeugt werden.")
            }
            try checkAllocation()
            let object = STObject(stClass)
            objects.append(object)
            return try send(.object(object), "initialize", [])
        default: return nil
        }
    }

    func subclass(of superclass: STClass, name: String, fields source: String) throws -> STClass {
        guard superclass.name == "Object" || !Self.builtinNames.contains(superclass.name) else { throw SmalltalkError("Unterklassen primitiver Klassen sind noch nicht implementiert.") }
        guard name.first?.isUppercase == true && name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else {
            throw SmalltalkError("Klassenname muss mit einem Großbuchstaben beginnen.")
        }
        guard globals[name] == nil else { throw SmalltalkError("\(name) existiert bereits.") }
        guard classes.count < 128 else { throw SmalltalkError("Maximal 128 Klassen pro Sitzung.") }
        let fields = source.split(whereSeparator: \.isWhitespace).map(String.init)
        var parser = try Parser("| \(fields.joined(separator: " ")) |")
        let validated = try parser.workspace().temporaries
        guard validated == fields, Set(fields).isDisjoint(with: superclass.fields), fields.count + superclass.fields.count <= 64 else {
            throw SmalltalkError("Instanzvariablen sind ungültig, doppelt oder zu zahlreich (maximal 64).")
        }
        let stClass = STClass(name, superclass: superclass, fields: fields)
        classes[name] = stClass
        globals[name] = .classObject(stClass)
        return stClass
    }

    static let builtinNames: Set<String> = ["Object", "Class", "UndefinedObject", "Boolean", "True", "False", "Number", "Integer", "SmallInteger", "String", "Symbol", "Array", "BlockClosure", "Transcript"]

    func integerPrimitive(_ n: Int64, _ selector: String, _ args: [Value]) throws -> Value? {
        switch selector {
        case "+": return .integer(try checked(n.addingReportingOverflow(integer(args[0]))))
        case "-": return .integer(try checked(n.subtractingReportingOverflow(integer(args[0]))))
        case "*": return .integer(try checked(n.multipliedReportingOverflow(by: integer(args[0]))))
        case "/", "//", "\\\\":
            let divisor = try integer(args[0])
            guard divisor != 0 else { throw SmalltalkError("Division durch null.") }
            guard !(n == .min && divisor == -1) else { throw SmalltalkError("Ganzzahlüberlauf (64 Bit).") }
            let quotient = n / divisor
            let remainder = n % divisor
            if selector == "/" {
                guard remainder == 0 else { throw SmalltalkError("Brüche sind noch nicht implementiert; verwende // für Ganzzahldivision.") }
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
            guard step != 0 else { throw SmalltalkError("Schrittweite darf nicht null sein.") }
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
        guard case .integer(let n) = value else { throw SmalltalkError("Ganzzahl erwartet, erhalten: \(printValue(value)).") }
        return n
    }

    func boolean(_ value: Value) throws -> Bool {
        guard case .boolean(let b) = value else { throw SmalltalkError("true oder false erwartet, erhalten: \(printValue(value)).") }
        return b
    }

    func string(_ value: Value) throws -> String {
        guard case .string(let s) = value else { throw SmalltalkError("String erwartet.") }
        return s
    }

    func symbol(_ value: Value) throws -> String {
        guard case .symbol(let s) = value else { throw SmalltalkError("Symbol erwartet, zum Beispiel #Counter.") }
        return s
    }

    func index(_ value: Value, count: Int) throws -> Int {
        let number = try integer(value)
        guard number >= 1 && number <= count else { throw SmalltalkError("Index \(number) liegt außerhalb von 1…\(count).") }
        return Int(number - 1)
    }

    func checked(_ result: (partialValue: Int64, overflow: Bool)) throws -> Int64 {
        guard !result.overflow else { throw SmalltalkError("Ganzzahlüberlauf (64 Bit).") }
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

    func appendTranscript(_ text: String) throws {
        guard transcript.utf8.count + text.utf8.count <= 65_536 else { throw SmalltalkError("Transcript-Ausgabe ist auf 64 KiB pro Ausführung begrenzt.") }
        transcript += text
    }
}
