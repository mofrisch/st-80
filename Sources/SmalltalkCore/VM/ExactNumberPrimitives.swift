extension SmalltalkRuntime {
    static let exactBinarySelectors: Set<String> = ["+", "-", "*", "/", "//", "\\\\", "<", ">", "<=", ">="]

    func integerProtocol(_ number: BigInteger, _ selector: String, _ arguments: [Value]) throws -> Value? {
        switch selector {
        case "_integerSqrt":
            return integerValue(try number.roundedSquareRoot(charge: chargeNumericWork))
        case "bitAnd:", "bitOr:", "bitXor:":
            let operand = try unboundedInteger(arguments[0])
            try chargeNumericWork(max(number.wordCount, operand.wordCount))
            if selector == "bitAnd:" { return integerValue(number.bitAnd(operand)) }
            if selector == "bitOr:" { return integerValue(number.bitOr(operand)) }
            return integerValue(number.bitXor(operand))
        case "bitShift:":
            let shift = try unboundedInteger(arguments[0])
            if shift.isNegative {
                guard let count = shift.magnitude.int64, count < number.bitWidth else { return .integer(0) }
                try chargeNumericWork(number.wordCount)
                return integerValue(number.shiftedRight(Int(count)))
            }
            if number.isZero { return .integer(0) }
            guard let count = shift.int64, count <= Int.max - number.bitWidth else {
                throw SmalltalkError("Bit shift is outside the supported range.")
            }
            try chargeNumericWork(number.wordCount + Int(count) / 29 + 1)
            return integerValue(number.shiftedLeft(Int(count)))
        case "bitAt:", "bitAt:put:":
            let index = try unboundedInteger(arguments[0])
            guard index > .zero else { throw SmalltalkError("Bit indices start at 1.") }
            let bit = index.int64.flatMap { $0 <= number.bitWidth ? Int($0 - 1) : nil }
            try chargeNumericWork(number.wordCount)
            let set = bit.map { !number.shiftedRight($0).bitAnd(.one).isZero } ?? false
            if selector == "bitAt:" { return .integer(set ? 1 : 0) }
            let replacement = try !unboundedInteger(arguments[1]).bitAnd(.one).isZero
            if replacement == set { return integerValue(number) }
            guard let count = index.int64 else { throw SmalltalkError("Bit index is outside the supported range.") }
            try chargeNumericWork(Int(count) / 29 + 1)
            return integerValue(number.bitXor(.one.shiftedLeft(Int(count - 1))))
        case "highBit":
            return .integer(Int64(number.bitWidth))
        case "printStringRadix:":
            let radix = try integer(arguments[0])
            guard (2...36).contains(radix) else { throw SmalltalkError("Radix must be between 2 and 36.") }
            guard number.bitWidth <= 65_536 * (radix == 2 ? 1 : 6) else { throw SmalltalkError("The integer representation is too long.") }
            let text = try number.radixString(Int(radix), charge: chargeNumericWork)
            guard text.utf8.count <= 65_536 else { throw SmalltalkError("The integer representation is too long.") }
            return .string(text)
        default: return nil
        }
    }

    func largeIntegerPrimitive(_ number: BigInteger, _ selector: String, _ arguments: [Value]) throws -> Value? {
        if case .scaledDecimal(let decimal)? = arguments.first, Self.exactBinarySelectors.contains(selector) {
            return try scaledDecimalBinary(ScaledDecimal(number, scale: 0), selector, decimal)
        }
        if case .float? = arguments.first, Self.exactBinarySelectors.contains(selector) {
            return try floatPrimitive(finiteDouble(number.doubleValue), selector, arguments)
        }
        if case .fraction? = arguments.first, Self.exactBinarySelectors.contains(selector) {
            return try fractionPrimitive(ExactFraction(number, .one, charge: chargeNumericWork), selector, arguments)
        }
        if Self.exactBinarySelectors.contains(selector) {
            let operand = try unboundedInteger(arguments[0])
            try chargeNumericWork(max(number.wordCount, operand.wordCount))
            switch selector {
            case "+": return integerValue(number + operand)
            case "-": return integerValue(number - operand)
            case "*": return integerValue(try number.multiplied(by: operand, charge: chargeNumericWork))
            case "/": return try fractionValue(number, operand)
            case "//", "\\\\":
                let division = try floorDivision(number, by: operand)
                return integerValue(selector == "//" ? division.quotient : division.remainder)
            case "<": return .boolean(number < operand)
            case ">": return .boolean(number > operand)
            case "<=": return .boolean(number <= operand)
            default: return .boolean(number >= operand)
            }
        }
        switch selector {
        case "negated": return integerValue(-number)
        case "abs": return integerValue(number.magnitude)
        case "squared": return integerValue(try number.multiplied(by: number, charge: chargeNumericWork))
        case "numerator": return integerValue(number)
        case "denominator": return .integer(1)
        case "asFloat", "asFloatE", "asFloatD", "asFloatQ": return try finiteFloat(number.doubleValue)
        case "asScaledDecimal:": return try convertToScaledDecimal(.largeInteger(number), scale: arguments[0])
        case "asCharacter": throw SmalltalkError("Invalid Unicode scalar code point.")
        case "timesRepeat:":
            var remaining = number
            while remaining > .zero {
                _ = try invokeBlock(arguments[0])
                try chargeNumericWork(remaining.wordCount)
                remaining = remaining - .one
            }
            return integerValue(number)
        case "to:do:", "to:by:do:":
            let hasStep = selector == "to:by:do:"
            let increment = hasStep ? arguments[1] : .integer(1)
            let block = arguments[hasStep ? 2 : 1]
            if !arguments[0].isInteger || !increment.isInteger {
                let receiver = integerValue(number)
                let interval = try send(receiver, "to:by:", [arguments[0], increment])
                _ = try send(interval, "do:", [block])
                return receiver
            }
            let end = try unboundedInteger(arguments[0])
            let step = try unboundedInteger(increment)
            guard !step.isZero else { throw SmalltalkError("The step size must be nonzero.") }
            var current = number
            while step.isNegative ? current >= end : current <= end {
                _ = try invokeBlock(block, [integerValue(current)])
                try chargeNumericWork(max(current.wordCount, step.wordCount, end.wordCount))
                current = current + step
            }
            return integerValue(number)
        default: return nil
        }
    }

    func fractionValue(_ numerator: BigInteger, _ denominator: BigInteger, factory: Bool = false) throws -> Value {
        let fraction = try ExactFraction(numerator, denominator, charge: chargeNumericWork)
        if fraction.denominator == .one && (!factory || numerator == denominator || denominator.magnitude == .one) {
            return integerValue(fraction.numerator)
        }
        return .fraction(fraction)
    }

    func floorDivision(_ numerator: BigInteger, by denominator: BigInteger) throws -> (quotient: BigInteger, remainder: BigInteger) {
        let (quotient, remainder) = try numerator.divided(by: denominator, charge: chargeNumericWork)
        if !remainder.isZero && numerator.isNegative != denominator.isNegative {
            return (quotient - .one, remainder + denominator)
        }
        return (quotient, remainder)
    }

    func fractionPrimitive(_ number: ExactFraction, _ selector: String, _ arguments: [Value]) throws -> Value? {
        if case .float? = arguments.first, Self.exactBinarySelectors.contains(selector) {
            return try floatPrimitive(finiteDouble(number.doubleValue(charge: chargeNumericWork)), selector, arguments)
        }
        if Self.exactBinarySelectors.contains(selector) {
            let operand: ExactFraction
            if case .fraction(let fraction) = arguments[0] {
                operand = fraction
            } else if case .scaledDecimal(let decimal) = arguments[0] {
                operand = try fractionFromDecimal(decimal)
            } else {
                operand = try ExactFraction(unboundedInteger(arguments[0]), .one, charge: chargeNumericWork)
            }
            return try fractionBinary(number, selector, operand)
        }
        switch selector {
        case "numerator": return integerValue(number.numerator)
        case "denominator": return integerValue(number.denominator)
        case "negated": return .fraction(number.negated)
        case "abs": return .fraction(number.magnitude)
        case "squared": return .fraction(try number.squared(charge: chargeNumericWork))
        case "_exactSqrt": return try finiteFloat(number.numerator.squareRoot(dividedBy: number.denominator, charge: chargeNumericWork))
        case "asFloat", "asFloatE", "asFloatD", "asFloatQ":
            return try finiteFloat(number.doubleValue(charge: chargeNumericWork))
        case "asScaledDecimal:": return try convertToScaledDecimal(.fraction(number), scale: arguments[0])
        case "floor": return integerValue(try floorDivision(number.numerator, by: number.denominator).quotient)
        case "truncated", "ceiling", "rounded":
            let (quotient, remainder) = try number.numerator.divided(by: number.denominator, charge: chargeNumericWork)
            if selector == "ceiling" && !remainder.isZero && !number.numerator.isNegative {
                return integerValue(quotient + .one)
            }
            if selector == "rounded" && remainder.magnitude + remainder.magnitude >= number.denominator {
                return integerValue(number.numerator.isNegative ? quotient - .one : quotient + .one)
            }
            return integerValue(quotient)
        default: return nil
        }
    }

    func fractionBinary(_ lhs: ExactFraction, _ selector: String, _ rhs: ExactFraction) throws -> Value {
        if selector == "*" {
            return try fractionValue(lhs.numerator.multiplied(by: rhs.numerator, charge: chargeNumericWork),
                                     lhs.denominator.multiplied(by: rhs.denominator, charge: chargeNumericWork))
        }
        let left = try lhs.numerator.multiplied(by: rhs.denominator, charge: chargeNumericWork)
        let right = try rhs.numerator.multiplied(by: lhs.denominator, charge: chargeNumericWork)
        switch selector {
        case "<": return .boolean(left < right)
        case ">": return .boolean(left > right)
        case "<=": return .boolean(left <= right)
        case ">=": return .boolean(left >= right)
        case "/": return try fractionValue(left, right)
        case "//": return integerValue(try floorDivision(left, by: right).quotient)
        case "\\\\":
            let remainder = try floorDivision(left, by: right).remainder
            return try fractionValue(remainder, lhs.denominator.multiplied(by: rhs.denominator, charge: chargeNumericWork))
        default:
            return try fractionValue(selector == "+" ? left + right : left - right,
                                     lhs.denominator.multiplied(by: rhs.denominator, charge: chargeNumericWork))
        }
    }
}
