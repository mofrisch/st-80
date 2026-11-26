extension SmalltalkRuntime {
    static let exactBinarySelectors: Set<String> = ["+", "-", "*", "/", "//", "\\\\", "<", ">", "<=", ">="]

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
            let end = try unboundedInteger(arguments[0])
            let step = selector == "to:do:" ? .one : try unboundedInteger(arguments[1])
            let block = arguments[selector == "to:do:" ? 1 : 2]
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
            return try floatPrimitive(finiteDouble(number.doubleValue), selector, arguments)
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
        case "negated": return try fractionValue(-number.numerator, number.denominator)
        case "abs": return try fractionValue(number.numerator.magnitude, number.denominator)
        case "squared": return try fractionBinary(number, "*", number)
        case "asFloat", "asFloatE", "asFloatD", "asFloatQ": return try finiteFloat(number.doubleValue)
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
