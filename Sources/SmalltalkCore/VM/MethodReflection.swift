import Foundation

extension SmalltalkRuntime {
    static let primitiveDescriptions: [String: [String: String]] = [
        "Object": [
            "class": "Returns the receiver's class.", "yourself": "Returns the receiver.",
            "copy": "Returns an independent shallow copy, or the receiver for an identity object.",
            "hash": "Returns a hash compatible with value equality.",
            "identityHash": "Returns a stable hash compatible with identity.",
            "printString": "Returns a readable representation.", "=": "Compares values.", "==": "Compares identity. Strings are treated as values.",
            "~=": "Tests whether values differ.", "~~": "Tests whether the objects differ in identity.",
            "isNil": "Tests whether the receiver is nil.", "notNil": "Tests whether the receiver is non-nil.",
            "ifNil:": "Evaluates a block if the receiver is nil.", "ifNotNil:": "Evaluates a block if the receiver is non-nil.",
            "respondsTo:": "Tests whether the receiver understands a message.", "perform:": "Sends a message by selector.",
            "perform:with:": "Sends a message by selector with one argument.",
            "perform:with:with:": "Sends a message by selector with two arguments.",
            "perform:with:with:with:": "Sends a message by selector with three arguments.",
            "perform:withArguments:": "Sends a message by selector with the elements of a collection as arguments.",
            "error:line:column:": "Reports an error at a source position.",
        ],
        "Class": [
            "new": "Creates an object and sends initialize.", "new:": "Creates a fixed-size array or string.",
            "name": "Returns the class name.", "superclass": "Returns the superclass.", "subclasses": "Returns the immediate subclasses.",
            "allSuperclasses": "Returns all superclasses.", "allSubclasses": "Returns all subclasses.",
            "subclass:instanceVariableNames:": "Creates a subclass.",
            "subclass:instanceVariableNames:classInstanceVariableNames:": "Creates a subclass with per-class instance variables.",
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
        "Metaclass": [
            "instanceClass": "Returns the class whose metaclass is the receiver.",
            "instanceVariableNames:": "Changes the receiver's declared instance variable names.",
        ],
        "Integer": [
            "+": "Addition.", "-": "Subtraction.", "*": "Multiplication.",
            "/": "Exact division, returning a fraction for a non-integral quotient.", "//": "Division rounded down.",
            "\\\\": "Remainder from division rounded down.", "<": "Less than.", ">": "Greater than.",
            "<=": "Less than or equal to.", ">=": "Greater than or equal to.",
            "negated": "Returns the negated value.", "abs": "Returns the absolute value.", "squared": "Returns the square.",
            "asCharacter": "Returns the character for the receiver's Unicode code point.",
            "numerator": "Returns the integer itself.", "denominator": "Returns one.",
            "asFloat": "Converts the integer to binary64.", "asFloatE": "Converts the integer to binary64.",
            "asFloatD": "Converts the integer to binary64.", "asFloatQ": "Converts the integer to binary64.",
            "asScaledDecimal:": "Converts the integer to a scaled decimal with scale zero.",
            "timesRepeat:": "Repeats a block.", "to:do:": "Iterates through the final value, inclusive.",
            "to:by:do:": "Iterates with the specified step size.",
            "bitAnd:": "Combines the bits using logical AND.", "bitOr:": "Combines the bits using logical OR.",
            "bitXor:": "Combines the bits using exclusive OR.", "bitShift:": "Shifts the integer by a signed number of bits.",
            "bitAt:": "Returns a bit. Position one is the least significant bit.",
            "bitAt:put:": "Returns an integer with one bit replaced.", "highBit": "Returns the most significant bit position.",
            "printStringRadix:": "Formats the integer in the indicated radix.",
        ],
        "Boolean": [
            "not": "Negation.", "ifTrue:": "Evaluates a block if the receiver is true.", "ifFalse:": "Evaluates a block if the receiver is false.",
            "ifTrue:ifFalse:": "Evaluates one of two blocks.", "ifFalse:ifTrue:": "Evaluates one of two blocks.",
            "and:": "Short-circuiting logical AND.", "or:": "Short-circuiting logical OR.",
            "&": "Boolean conjunction.", "|": "Boolean disjunction.",
            "eqv:": "Boolean equivalence.", "xor:": "Boolean exclusive OR.",
        ],
        "Fraction": [
            "numerator": "Returns the reduced numerator.", "denominator": "Returns the positive reduced denominator.",
            "+": "Exact addition.", "-": "Exact subtraction.", "*": "Exact multiplication.", "/": "Exact division.",
            "//": "Division rounded down to an integer.", "\\\\": "Remainder from division rounded down.",
            "<": "Less than.", ">": "Greater than.", "<=": "Less than or equal to.", ">=": "Greater than or equal to.",
            "negated": "Returns the negated fraction.", "abs": "Returns the absolute value.", "squared": "Returns the exact square.",
            "asFloat": "Converts the fraction to binary64.", "asFloatE": "Converts the fraction to binary64.",
            "asFloatD": "Converts the fraction to binary64.", "asFloatQ": "Converts the fraction to binary64.",
            "asScaledDecimal:": "Rounds the fraction to a specified decimal scale.",
            "floor": "Rounds down to an integer.", "ceiling": "Rounds up to an integer.",
            "rounded": "Rounds to the nearest integer.", "truncated": "Rounds toward zero to an integer.",
        ],
        "ScaledDecimal": [
            "scale": "Returns the number of fractional digits, including trailing zeros.",
            "+": "Addition.", "-": "Subtraction.", "*": "Multiplication.", "/": "Division.",
            "//": "Division rounded down to an integer.", "\\\\": "Remainder from division rounded down.",
            "<": "Less than.", ">": "Greater than.", "<=": "Less than or equal to.", ">=": "Greater than or equal to.",
            "negated": "Returns the negated value.", "abs": "Returns the absolute value.",
            "squared": "Returns the exact square.", "reciprocal": "Divides one by the receiver.",
            "negative": "Tests whether the receiver is negative.", "positive": "Tests whether the receiver is nonnegative.",
            "strictlyPositive": "Tests whether the receiver is greater than zero.", "sign": "Returns negative one, zero, or one.",
            "asFraction": "Converts the value exactly to a rational.", "asScaledDecimal:": "Rounds to a specified decimal scale.",
            "asFloat": "Converts the decimal to binary64.", "asFloatE": "Converts the decimal to binary64.",
            "asFloatD": "Converts the decimal to binary64.", "asFloatQ": "Converts the decimal to binary64.",
            "asInteger": "Rounds to the nearest integer.", "rounded": "Rounds to the nearest integer.",
            "ceiling": "Rounds up to an integer.", "floor": "Rounds down to an integer.",
            "truncated": "Rounds toward zero to an integer.", "integerPart": "Returns the integer part as a scaled decimal.",
            "fractionPart": "Returns the remainder after floor division by one.",
        ],
        "Float": [
            "+": "Addition.", "-": "Subtraction.", "*": "Multiplication.", "/": "Floating-point division.",
            "//": "Division rounded down to an integer.", "\\\\": "Remainder from division rounded down.",
            "<": "Less than.", ">": "Greater than.", "<=": "Less than or equal to.", ">=": "Greater than or equal to.",
            "negated": "Returns the negated number.", "abs": "Returns the absolute value.", "squared": "Returns the square.",
            "asFloat": "Returns the binary64 value.", "asFloatE": "Returns the binary64 value.",
            "asFloatD": "Returns the binary64 value.", "asFloatQ": "Returns the binary64 value.",
            "asScaledDecimal:": "Rounds the binary64 value to a specified decimal scale.",
            "ceiling": "Rounds up to an integer.", "floor": "Rounds down to an integer.",
            "truncated": "Rounds toward zero to an integer.", "rounded": "Rounds to the nearest integer.",
            "sqrt": "Square root.", "exp": "Exponential function.", "ln": "Natural logarithm.",
            "arcSin": "Arcsine.", "arcCos": "Arccosine.", "arcTan": "Arctangent.",
            "asFraction": "Converts the binary64 value exactly to a rational.",
            "sin": "Sine.", "cos": "Cosine.", "tan": "Tangent.",
        ],
        "String": [",": "Concatenates two strings.", "size": "Returns the number of Unicode code points.", "at:": "Returns the character at a one-based index.", "asString": "Returns the string.", "asSymbol": "Converts the string to a symbol.", "characters": "Returns an array of one-grapheme strings.",
            "asCharacter": "Converts a one-code-point string to a character.",
            "includes:": "Tests whether a character or substring is present.", "isLetter": "Tests whether the string is one letter.",
            "isNumber": "Tests whether the string is one numeric character.", "isASCIIDigit": "Tests whether the string is one ASCII digit.",
            "isLowercase": "Tests whether the string is one lowercase character.", "isWhitespace": "Tests whether the string is one whitespace character.",
            "isLineBreak": "Tests whether the string is a line break.", "asIntegerOrNil": "Parses a signed decimal integer.",
            "parseIntegerMagnitudeRadix:": "Parses unsigned literal digits for the compiler.",
            "parseFloatOrNil": "Parses a binary64 number for the compiler.",
            "parseScaledDecimalOrNil": "Parses a scaled decimal number for the compiler.",
            "at:put:": "Stores a character at a one-based position.", "do:": "Visits the characters in order.",
            "asLowercase": "Returns a lowercase string.", "asUppercase": "Returns an uppercase string.",
            "sameAs:": "Compares text ignoring case.", "_replaceCharacters:": "Replaces the characters of a writable string.",
            "<": "Collates before the argument.", "<=": "Collates before or the same as the argument.",
            ">": "Collates after the argument.", ">=": "Collates after or the same as the argument.",
            "min:": "Returns the earlier text.", "max:": "Returns the later text.", "between:and:": "Tests the inclusive collation range."],
        "Symbol": [
            "asString": "Returns the symbol name as a string.", "asSymbol": "Returns the receiver.",
            "size": "Returns the number of characters.", "at:": "Returns the character at a one-based position.",
            "do:": "Visits the characters in order.", "asLowercase": "Returns a lowercase string.",
            "asUppercase": "Returns an uppercase string.", "sameAs:": "Compares text ignoring case.",
            "<": "Collates before the argument.", "<=": "Collates before or the same as the argument.",
            ">": "Collates after the argument.", ">=": "Collates after or the same as the argument.",
            "min:": "Returns the earlier text.", "max:": "Returns the later text.", "between:and:": "Tests the inclusive collation range.",
        ],
        "Character": [
            "asString": "Returns a string containing the character.", "codePoint": "Returns the Unicode code point.",
            "asLowercase": "Returns the lowercase character when there is a single-code-point mapping.",
            "asUppercase": "Returns the uppercase character when there is a single-code-point mapping.",
            "isAlphaNumeric": "Tests for a letter or a decimal digit.", "isDigit": "Tests for a decimal digit.",
            "isLetter": "Tests for a letter.", "isLowercase": "Tests for lowercase.", "isUppercase": "Tests for uppercase.",
            "hash": "Returns the character's code point as its hash.", "identityHash": "Returns the character's code point as its identity hash.",
        ],
        "Array": ["size": "Returns the number of elements.", "at:": "Returns the element at a one-based index.", "at:put:": "Sets an element.", "do:": "Visits each element.", "collect:": "Transforms each element.", "select:": "Filters elements.", "isEmpty": "Tests whether the array is empty.", "includes:": "Tests whether the array contains an element.",
            "joinedStringFrom:to:": "Joins the strings in an index range."],
        "SequenceableCollection": [
            "=": "Compares collections of the same class by their indexed elements.",
            "hash": "Returns a hash compatible with equality, including for cyclic collections.",
        ],
        "OrderedCollection": [
            "_spliceAt:remove:with:": "Splices the active storage range and updates the collection size.",
        ],
        "CollectionStream": [
            "_commitWrite:": "Updates the stream storage and advances its position together.",
        ],
        "FileStream": [
            "_openFile:mode:check:type:": "Opens the external backing file.",
            "_closeFile": "Flushes and closes the external backing file.",
            "_fileContents": "Returns all file elements without advancing the stream.",
            "_fileIsEmpty": "Tests whether the external file is empty.",
            "_filePosition": "Returns the number of elements before the cursor.",
            "_seekFile:": "Moves the cursor to an element position.",
            "_seekFileToEnd": "Moves the cursor to the end of the file.",
        ],
        "ReadFileStream": [
            "_fileAtEnd": "Tests whether the cursor is at the end of the file.",
            "_peekFileElement": "Reads the next file element without advancing.",
            "_readFileElement": "Reads the next file element and advances.",
            "_readFileElements:": "Reads a bounded sequence of file elements.",
            "_skipFileElements:": "Advances by up to the requested number of file elements.",
            "_scanFileUntil:collecting:": "Advances to the first matching element, optionally collecting the prefix.",
        ],
        "WriteFileStream": [
            "_writeFileElements:": "Writes a sequence of elements at the current position.",
            "_flushFile": "Synchronizes the changes with the external file.",
        ],
        "BlockClosure": [
            "value": "Evaluates the block.", "value:": "Evaluates the block with one argument.", "value:value:": "Evaluates the block with two arguments.",
            "argumentCount": "Returns the number of block arguments.", "valueWithArguments:": "Evaluates the block with the elements of a collection as arguments.",
            "on:do:": "Evaluates the block in the scope of an exception handler.",
            "ensure:": "Runs a cleanup block when evaluation finishes or unwinds.", "ifCurtailed:": "Runs a cleanup block only if evaluation unwinds.",
            "whileTrue": "Evaluates the block repeatedly until it returns false.", "whileFalse": "Evaluates the block repeatedly until it returns true.",
            "whileTrue:": "Repeats while the block evaluates to true.", "whileFalse:": "Repeats while the block evaluates to false.",
        ],
        "Exception": [
            "_signalException": "Finds and activates the closest matching exception handler.",
            "_failUnhandledException": "Ends the evaluation and reports the unhandled exception.",
            "isNested": "Tests for an enclosing handler that accepts the exception.",
            "outer": "Invokes the enclosing handler and receives its resumption value.",
            "pass": "Continues the search outside the current handler.",
            "resignalAs:": "Signals a replacement in the original signaling context.",
            "resume": "Continues from the signal with nil.",
            "resume:": "Continues from the signal with a value.",
            "retry": "Repeats the protected block.",
            "retryUsing:": "Evaluates a replacement protected block.",
            "return": "Exits the protected block with nil.",
            "return:": "Exits the protected block with the argument.",
        ],
        "Warning": [
            "_confirmWarning:title:continue:abort:": "Asks the host to continue or abort. Returns nil when no prompt is available.",
        ],
        "Transcript": ["record:": "Records transcript output for the current evaluation."],
    ]

    func primitiveSelectors(_ stClass: STClass) -> Set<String> {
        let own = Set((Self.primitiveDescriptions[stClass.name] ?? [:]).keys)
        return own.union(stClass.superclass.map(primitiveSelectors) ?? [])
    }

    func reflectedMethods(on target: STClass, side: MethodSide) -> [MethodInfo] {
        guard side == .instance || target.instanceClass == nil else { return [] }
        var methods = target[side].map { MethodInfo(selector: $0.key, source: $0.value.source, isPrimitive: false) }
        if side == .instance {
            for (selector, description) in Self.primitiveDescriptions[target.name] ?? [:] where target.methods[selector] == nil {
                methods.append(MethodInfo(selector: selector, source: primitiveSource(selector, description), isPrimitive: true))
            }
        }
        return methods.sorted { $0.selector < $1.selector }
    }

    func reflectedMethodSource(_ selector: String, on target: STClass, side: MethodSide) -> String? {
        guard side == .instance || target.instanceClass == nil else { return nil }
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
