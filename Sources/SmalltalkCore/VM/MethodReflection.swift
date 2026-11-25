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
}
