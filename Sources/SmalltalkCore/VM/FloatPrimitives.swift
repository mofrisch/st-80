import Foundation

extension SmalltalkRuntime {
    static func floatLiteralText(_ number: Double) -> String {
        let spelling = String(number)
        guard let exponent = spelling.firstIndex(of: "e") else { return spelling }
        var mantissa = String(spelling[..<exponent])
        if !mantissa.contains(".") { mantissa += ".0" }
        let power = spelling[spelling.index(after: exponent)...]
        return mantissa + "e" + (power.first == "+" ? power.dropFirst() : power)
    }

    func finiteDouble(_ number: Double) throws -> Double {
        guard number.isFinite else { throw SmalltalkError("Floating-point result is outside the supported range.") }
        return number
    }

    func finiteFloat(_ number: Double) throws -> Value { .float(try finiteDouble(number)) }

    private func floatingNumber(_ value: Value) throws -> Double {
        switch value {
        case .integer(let number): return Double(number)
        case .largeInteger(let number): return try finiteDouble(number.doubleValue)
        case .fraction(let number): return try finiteDouble(number.doubleValue(charge: chargeNumericWork))
        case .scaledDecimal(let number): return try finiteDouble(number.doubleValue)
        case .float(let number): return number
        default: throw SmalltalkError("Expected a number.")
        }
    }

    func floatPrimitive(_ number: Double, _ selector: String, _ arguments: [Value]) throws -> Value? {
        switch selector {
        case "+": return try finiteFloat(number + floatingNumber(arguments[0]))
        case "-": return try finiteFloat(number - floatingNumber(arguments[0]))
        case "*": return try finiteFloat(number * floatingNumber(arguments[0]))
        case "/", "//", "\\\\", "_floatRem:":
            let divisor = try floatingNumber(arguments[0])
            guard divisor != 0 else { throw SmalltalkError("Division by zero.") }
            if selector == "/" { return try finiteFloat(number / divisor) }
            if selector == "//" {
                let dividend = Self.dyadicComponents(number)
                let denominator = Self.dyadicComponents(divisor)
                let shift = dividend.exponent - denominator.exponent
                let top = dividend.coefficient.shiftedLeft(max(0, shift))
                let bottom = denominator.coefficient.shiftedLeft(max(0, -shift))
                return integerValue(try floorDivision(top, by: bottom).quotient)
            }
            let remainder = number.truncatingRemainder(dividingBy: divisor)
            if selector == "_floatRem:" { return .float(remainder) }
            return .float(remainder != 0 && remainder.sign != divisor.sign ? remainder + divisor : remainder)
        case "<": return .boolean(try number < floatingNumber(arguments[0]))
        case ">": return .boolean(try number > floatingNumber(arguments[0]))
        case "<=": return .boolean(try number <= floatingNumber(arguments[0]))
        case ">=": return .boolean(try number >= floatingNumber(arguments[0]))
        case "negated": return .float(-number)
        case "abs": return .float(abs(number))
        case "squared": return try finiteFloat(number * number)
        case "asFloat", "asFloatE", "asFloatD", "asFloatQ": return .float(number)
        case "asFraction":
            let (coefficient, exponent) = Self.dyadicComponents(number)
            if exponent >= 0 { return integerValue(coefficient.shiftedLeft(exponent)) }
            return try fractionValue(coefficient, .one.shiftedLeft(-exponent))
        case "asScaledDecimal:": return try convertToScaledDecimal(.float(number), scale: arguments[0])
        case "ceiling", "floor", "truncated", "rounded":
            let rule: FloatingPointRoundingRule
            switch selector {
            case "ceiling": rule = .up
            case "floor": rule = .down
            case "truncated": rule = .towardZero
            default: rule = .toNearestOrAwayFromZero
            }
            guard let rounded = BigInteger(exactly: number.rounded(rule)) else { throw SmalltalkError("Invalid floating-point integer conversion.") }
            return integerValue(rounded)
        case "sqrt": return try finiteFloat(number.squareRoot())
        case "exp": return try finiteFloat(exp(number))
        case "ln": return try finiteFloat(log(number))
        case "_floorLog:":
            return try integerValue(floorLogarithm(number, base: arguments[0]))
        case "arcCos": return try finiteFloat(acos(number))
        case "arcSin": return try finiteFloat(asin(number))
        case "arcTan": return try finiteFloat(atan(number))
        case "sin": return try finiteFloat(sin(number))
        case "cos": return try finiteFloat(cos(number))
        case "tan": return try finiteFloat(tan(number))
        default: return nil
        }
    }

    private static func dyadicComponents(_ number: Double) -> (coefficient: BigInteger, exponent: Int) {
        let implicitBit: UInt64 = number.isNormal ? 1 << Double.significandBitCount : 0
        let significand = Int64(number.significandBitPattern + implicitBit)
        return (BigInteger(number.sign == .minus ? -significand : significand),
                max(Int(number.exponentBitPattern), 1) - 1_075)
    }

    private func floorLogarithm(_ number: Double, base: Value) throws -> BigInteger {
        let (numerator, denominator) = try logarithmBaseRatio(base)
        guard number > 0, numerator > denominator else {
            throw SmalltalkError("Floor logarithm requires a positive receiver and a base greater than one.")
        }
        if number == 1 { return .zero }
        let difference = numerator - denominator
        let baseLog: Double
        if difference < denominator {
            // Subtract exactly so a rational base rounding to binary64 one still has a nonzero logarithm.
            baseLog = try log1p(difference.doubleValue(dividedBy: denominator, charge: chargeNumericWork))
        } else {
            baseLog = try log(numerator.doubleValue(dividedBy: denominator, charge: chargeNumericWork))
        }
        let estimate = BigInteger(exactly: (log(number) / baseLog).rounded(.down)) ?? .zero
        let receiver = BinaryPowerBound(number)
        // Work with the reciprocal for negative exponents. A power can then be
        // compared directly with a binary64 receiver, including exact equality.
        let inverse = number < 1
        let top = inverse ? denominator : numerator
        let bottom = inverse ? numerator : denominator
        var bounds: [Int: (lower: BinaryPowerBound, upper: BinaryPowerBound)] = [:]

        func baseBounds(precision: Int) throws -> (lower: BinaryPowerBound, upper: BinaryPowerBound) {
            if let cached = bounds[precision] { return cached }
            let exponent = top.bitWidth - bottom.bitWidth - precision
            let scaledNumerator = top.shiftedLeft(max(0, -exponent))
            let scaledDenominator = bottom.shiftedLeft(max(0, exponent))
            let (coefficient, remainder) = try scaledNumerator.divided(by: scaledDenominator, charge: chargeNumericWork)
            let lower = BinaryPowerBound(coefficient: coefficient, exponent: exponent)
            let upper = remainder.isZero ? lower : BinaryPowerBound(coefficient: coefficient + .one, exponent: exponent)
            bounds[precision] = (lower, upper)
            return (lower, upper)
        }

        func powerIsAtMostReceiver(_ exponent: BigInteger) throws -> Bool {
            if exponent.isZero { return number >= 1 }
            if exponent.isNegative && number >= 1 { return true }
            if !exponent.isNegative && number < 1 { return false }
            let power = exponent.magnitude
            var precision = 128
            while true {
                let base = try baseBounds(precision: precision)
                guard let lower = try base.lower.raised(to: power, precision: precision,
                                                        roundingUp: false, charge: chargeNumericWork) else { return inverse }
                if lower.compare(to: receiver) == .orderedDescending { return false }
                let upper = try base.upper.raised(to: power, precision: precision, roundingUp: true, charge: chargeNumericWork)
                if upper.map({ $0.compare(to: receiver) != .orderedDescending }) ?? inverse {
                    return true
                }
                precision *= 2
            }
        }

        // The floating-point logarithm is only a starting point. Search with exact integer
        // exponents so bases close to one work beyond binary64's consecutive integer range.
        var lower = estimate
        var upper = estimate
        var stride = BigInteger.one
        if try powerIsAtMostReceiver(estimate) {
            while try powerIsAtMostReceiver(estimate + stride) { stride = stride.shiftedLeft(1) }
            upper = estimate + stride
        } else {
            while try !powerIsAtMostReceiver(estimate - stride) { stride = stride.shiftedLeft(1) }
            lower = estimate - stride
        }
        while upper - lower > .one {
            let middle = lower + (upper - lower).shiftedRight(1)
            if try powerIsAtMostReceiver(middle) { lower = middle } else { upper = middle }
        }
        return lower
    }

    private func logarithmBaseRatio(_ base: Value) throws -> (BigInteger, BigInteger) {
        switch base {
        case .integer(let number): return (BigInteger(number), .one)
        case .largeInteger(let number): return (number, .one)
        case .fraction(let number): return (number.numerator, number.denominator)
        case .scaledDecimal(let number):
            let fraction = try fractionFromDecimal(number)
            return (fraction.numerator, fraction.denominator)
        case .float(let number):
            if number <= 1 { return (.zero, .one) }
            let bound = BinaryPowerBound(number)
            return (bound.coefficient.shiftedLeft(max(0, bound.exponent)), .one.shiftedLeft(max(0, -bound.exponent)))
        default:
            throw SmalltalkError("Expected a number.")
        }
    }
}

/// A dyadic value whose coefficient is rounded outward after each product.
private struct BinaryPowerBound {
    static let one = Self(coefficient: .one, exponent: 0)
    let coefficient: BigInteger
    let exponent: Int

    init(coefficient: BigInteger, exponent: Int) {
        self.coefficient = coefficient
        self.exponent = exponent
    }

    /// The binary64 argument is finite and strictly positive.
    init(_ number: Double) {
        let implicitBit: UInt64 = number.isNormal ? 1 << Double.significandBitCount : 0
        coefficient = BigInteger(Int64(number.significandBitPattern + implicitBit))
        exponent = max(Int(number.exponentBitPattern), 1) - 1_075
    }

    private var highestBit: Int { coefficient.bitWidth + exponent }

    func compare(to other: Self) -> ComparisonResult {
        if highestBit != other.highestBit { return highestBit < other.highestBit ? .orderedAscending : .orderedDescending }
        let left = coefficient.shiftedLeft(max(0, exponent - other.exponent))
        let right = other.coefficient.shiftedLeft(max(0, other.exponent - exponent))
        if left == right { return .orderedSame }
        return left < right ? .orderedAscending : .orderedDescending
    }

    /// nil means the bound is outside the entire binary64 comparison range.
    func raised(to power: BigInteger, precision: Int, roundingUp: Bool,
                charge: (Int) throws -> Void) throws -> Self? {
        var base = self
        var remaining = power
        var result = Self.one
        while !remaining.isZero {
            // The remaining multipliers are all on the same side of one.
            if abs(base.highestBit) > 4_096 { return nil }
            try charge(remaining.wordCount)
            if !remaining.bitAnd(.one).isZero {
                result = try result.multiplied(by: base, precision: precision, roundingUp: roundingUp, charge: charge)
                if abs(result.highestBit) > 4_096 { return nil }
            }
            remaining = remaining.shiftedRight(1)
            if !remaining.isZero {
                base = try base.multiplied(by: base, precision: precision, roundingUp: roundingUp, charge: charge)
            }
        }
        return result
    }

    private func multiplied(by other: Self, precision: Int, roundingUp: Bool, charge: (Int) throws -> Void) throws -> Self {
        let product = try coefficient.multiplied(by: other.coefficient, charge: charge)
        let discarded = max(0, product.bitWidth - precision)
        let truncated = product.shiftedRight(discarded)
        let coefficient = roundingUp && truncated.shiftedLeft(discarded) != product ? truncated + .one : truncated
        return Self(coefficient: coefficient, exponent: exponent + other.exponent + discarded)
    }
}
