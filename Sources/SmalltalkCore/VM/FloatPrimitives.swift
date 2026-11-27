import Foundation

extension SmalltalkRuntime {
    private static let largestFloatDigits = Array(BigInteger(exactly: Double.greatestFiniteMagnitude)!.description.utf8)
    private static let floatOrderingSelectors: Set<String> = ["<", ">", "<=", ">="]

    static func floatLiteralText(_ number: Double) -> String {
        let spelling = String(number)
        guard let exponent = spelling.firstIndex(of: "e") else { return spelling }
        var mantissa = String(spelling[..<exponent])
        if !mantissa.contains(".") { mantissa += ".0" }
        let power = spelling[spelling.index(after: exponent)...]
        return mantissa + "e" + (power.first == "+" ? power.dropFirst() : power)
    }

    func finiteDouble(_ number: Double) throws -> Double {
        guard number.isFinite else {
            throw SmalltalkError("Floating-point result is outside the supported range.", isFloatRangeError: true)
        }
        return number
    }

    func finiteFloat(_ number: Double) throws -> Value { .float(try finiteDouble(number)) }

    func parseFloatLiteral(_ source: String) -> Value {
        let spelling = source.replacingOccurrences(of: "d", with: "e").replacingOccurrences(of: "q", with: "e")
        guard let number = Double(spelling), number.isFinite else { return .nilValue }
        // Rounding to binary64 can hide values just above the largest finite Float.
        if abs(number) == Double.greatestFiniteMagnitude, !Self.floatLiteralWithinRange(spelling) { return .nilValue }
        return .float(number)
    }

    private static func floatLiteralWithinRange(_ spelling: String) -> Bool {
        let components = spelling.split(whereSeparator: { $0 == "e" || $0 == "E" })
        let mantissa = components[0].split(separator: ".", omittingEmptySubsequences: false)
        guard let exponent = components.count == 1 ? 0 : Int(components[1]) else { return false }
        let digits = mantissa.joined().utf8.filter { (48...57).contains($0) }.drop(while: { $0 == 48 })
        let fractionalDigits = mantissa.count == 2 ? mantissa[1].utf8.count : 0
        let (integerDigits, overflow) = (digits.count - fractionalDigits).addingReportingOverflow(exponent)
        guard !overflow else { return false }
        if integerDigits != largestFloatDigits.count { return integerDigits < largestFloatDigits.count }
        for (digit, limit) in zip(digits, largestFloatDigits) where digit != limit { return digit < limit }
        return digits.dropFirst(largestFloatDigits.count).allSatisfy { $0 == 48 }
    }

    private func floatingNumber(_ value: Value, forOrdering: Bool = false) throws -> Double {
        let approximation: Double
        switch value {
        case .integer(let number): approximation = Double(number)
        case .largeInteger(let number): approximation = number.doubleValue
        case .fraction(let number): approximation = try number.doubleValue(charge: chargeNumericWork)
        case .scaledDecimal(let number): approximation = number.doubleValue
        case .float(let number): approximation = number
        default: throw SmalltalkError("Expected a number.")
        }
        // In mixed ordering there is one finite Float. An out-of-range exact
        // operand sorts beyond it without producing a nonfinite Smalltalk value.
        return forOrdering ? approximation : try finiteDouble(approximation)
    }

    func mixedFloatPrimitive(_ receiver: Value, _ selector: String, _ arguments: [Value]) throws -> Value? {
        try floatPrimitive(floatingNumber(receiver, forOrdering: Self.floatOrderingSelectors.contains(selector)), selector, arguments)
    }

    func floatPrimitive(_ number: Double, _ selector: String, _ arguments: [Value]) throws -> Value? {
        switch selector {
        case "+": return try finiteFloat(number + floatingNumber(arguments[0]))
        case "-": return try finiteFloat(number - floatingNumber(arguments[0]))
        case "*": return try finiteFloat(number * floatingNumber(arguments[0]))
        case "/", "//", "\\\\", "_floatQuo:", "_floatRem:":
            let divisor = try floatingNumber(arguments[0])
            guard divisor != 0 else { return try signalZeroDivide(dividend: .float(number)) }
            if selector == "/" { return try finiteFloat(number / divisor) }
            if selector == "//" || selector == "_floatQuo:" {
                let dividend = Self.dyadicComponents(number)
                let denominator = Self.dyadicComponents(divisor)
                let shift = dividend.exponent - denominator.exponent
                let top = dividend.coefficient.shiftedLeft(max(0, shift))
                let bottom = denominator.coefficient.shiftedLeft(max(0, -shift))
                if selector == "_floatQuo:" {
                    return integerValue(try top.divided(by: bottom, charge: chargeNumericWork).quotient)
                }
                return integerValue(try floorDivision(top, by: bottom).quotient)
            }
            let remainder = number.truncatingRemainder(dividingBy: divisor)
            if selector == "_floatRem:" { return .float(remainder) }
            return .float(remainder != 0 && remainder.sign != divisor.sign ? remainder + divisor : remainder)
        case "<": return .boolean(try number < floatingNumber(arguments[0], forOrdering: true))
        case ">": return .boolean(try number > floatingNumber(arguments[0], forOrdering: true))
        case "<=": return .boolean(try number <= floatingNumber(arguments[0], forOrdering: true))
        case ">=": return .boolean(try number >= floatingNumber(arguments[0], forOrdering: true))
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
        case "_log:":
            switch arguments[0] {
            case .integer, .largeInteger, .fraction, .scaledDecimal:
                break
            default:
                let receiverLog = try send(.float(number), "ln", [])
                return try withRoots([receiverLog]) { _ in
                    let base = try send(arguments[0], "asFloat", [])
                    let baseLog = try send(base, "ln", [])
                    return try send(receiverLog, "/", [baseLog])
                }
            }
            let receiverLog = try finiteDouble(log(number))
            let (top, bottom) = try logarithmBaseRatio(arguments[0])
            guard top > .zero else { throw SmalltalkError("Logarithm requires a positive base.") }
            if top == bottom { return try signalZeroDivide(dividend: .float(receiverLog)) }
            let inverted = top < bottom
            if number == 1 { return .float(inverted ? -0.0 : 0.0) }
            let baseLog = try scaledLogarithm(inverted ? bottom : top, by: inverted ? top : bottom)
            let result = scalbn(receiverLog / baseLog.significand, -baseLog.exponent)
            return try finiteFloat(inverted ? -result : result)
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
        let baseLog = try scaledLogarithm(numerator, by: denominator)
        let quotient = scalbn(log(number) / baseLog.significand, -baseLog.exponent)
        let estimate = BigInteger(exactly: quotient.rounded(.down)) ?? .zero
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

    private func scaledLogarithm(_ top: BigInteger, by bottom: BigInteger) throws -> (significand: Double, exponent: Int32) {
        let difference = top - bottom
        if difference < bottom {
            let shift = difference.bitWidth - bottom.bitWidth
            if shift < -54 {
                // log1p(x) agrees with x to binary64 precision at this scale.
                let normalized = try difference.shiftedLeft(-shift).doubleValue(dividedBy: bottom, charge: chargeNumericWork)
                return (normalized, Int32(clamping: shift))
            }
            return (try log1p(difference.doubleValue(dividedBy: bottom, charge: chargeNumericWork)), 0)
        }
        let shift = top.bitWidth - bottom.bitWidth
        let normalized = try top.doubleValue(dividedBy: bottom.shiftedLeft(shift), charge: chargeNumericWork)
        return (log(normalized) + Double(shift) * log(2), 0)
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
