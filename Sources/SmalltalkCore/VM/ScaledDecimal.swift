import Foundation

/// A fixed-point value whose scale includes trailing fractional zeroes.
final class ScaledDecimal: Codable, Sendable, CustomStringConvertible {
    static let maximumScale = 1_024
    static let repeatingDivisionScale = 30

    let coefficient: BigInteger
    let scale: Int

    init(_ coefficient: BigInteger, scale: Int) throws {
        guard (0...Self.maximumScale).contains(scale) else {
            throw SmalltalkError("Scaled decimal scale must be between 0 and \(Self.maximumScale).")
        }
        self.coefficient = coefficient
        self.scale = scale
    }

    convenience init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let scale = try container.decode(Int.self, forKey: .scale)
        guard (0...Self.maximumScale).contains(scale) else {
            throw DecodingError.dataCorruptedError(forKey: .scale, in: container, debugDescription: "Invalid scaled decimal scale.")
        }
        try self.init(container.decode(BigInteger.self, forKey: .coefficient), scale: scale)
    }

    var description: String {
        var text = ""
        describe {
            text += $0
            return true
        }
        return text
    }

    func describe(_ append: (String) -> Bool) {
        var hasSpace = true
        coefficient.describe(decimalPlaces: scale) {
            hasSpace = append($0)
            return hasSpace
        }
        if hasSpace { _ = append("s\(scale)") }
    }

    var doubleValue: Double {
        let overflow = coefficient.isNegative ? -Double.infinity : Double.infinity
        // 10^(scale + 309) < 2^(4 * (scale + 309)). Bound the formatting
        // work while allowing a wide coefficient to scale back into range.
        guard coefficient.bitWidth <= 4 * (scale + 309) else { return overflow }
        return Double("\(coefficient)e-\(scale)") ?? overflow
    }
}

extension SmalltalkRuntime {
    func scaledDecimalLiteral(_ spelling: String) throws -> ScaledDecimal? {
        let parts = spelling.split(separator: "s", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let mantissa = parts[0].split(separator: ".", omittingEmptySubsequences: false)
        guard (1...2).contains(mantissa.count), mantissa.allSatisfy({ !$0.isEmpty }) else { return nil }
        let fractionalDigits = mantissa.count == 2 ? mantissa[1].utf8.count : 0
        guard let scale = parts[1].isEmpty ? fractionalDigits : Int(parts[1]),
              scale >= fractionalDigits, scale <= ScaledDecimal.maximumScale,
              parts[1].utf8.allSatisfy({ (48...57).contains($0) }),
              let coefficient = try BigInteger.parseMagnitude(mantissa.joined(), radix: 10, charge: chargeNumericWork) else { return nil }
        return try ScaledDecimal(shiftDecimal(coefficient, by: scale - fractionalDigits), scale: scale)
    }

    func convertToScaledDecimal(_ number: Value, scale argument: Value) throws -> Value {
        let requestedScale = try integer(argument)
        guard (0...Int64(ScaledDecimal.maximumScale)).contains(requestedScale) else {
            throw SmalltalkError("Scaled decimal scale must be between 0 and \(ScaledDecimal.maximumScale).")
        }
        let scale = Int(requestedScale)
        switch number {
        case .integer, .largeInteger:
            // ANSI's integer refinement specifies the exact integer with scale 0.
            return .scaledDecimal(try ScaledDecimal(unboundedInteger(number), scale: 0))
        case .scaledDecimal(let decimal):
            let precisionChange = scale - decimal.scale
            let coefficient = precisionChange >= 0
                ? try shiftDecimal(decimal.coefficient, by: precisionChange)
                : try roundedQuotient(decimal.coefficient, by: decimalFactor(-precisionChange))
            return .scaledDecimal(try ScaledDecimal(coefficient, scale: scale))
        case .fraction(let fraction):
            return try scaledQuotient(fraction.numerator, by: fraction.denominator, scale: scale)
        case .float(let float):
            let significand = Int64(float.significandBitPattern) + (float.isNormal ? 1 << 52 : 0)
            let exponent = float.isNormal ? Int(float.exponentBitPattern) - 1_075 : -1_074
            let numerator = BigInteger(float.sign == .minus ? -significand : significand)
            if exponent >= 0 {
                return try scaledQuotient(numerator.shiftedLeft(exponent), by: .one, scale: scale)
            }
            return try scaledQuotient(numerator, by: BigInteger.one.shiftedLeft(-exponent), scale: scale)
        default:
            throw SmalltalkError("Expected a number.")
        }
    }

    func scaledDecimalPrimitive(_ decimal: ScaledDecimal, _ selector: String, _ arguments: [Value]) throws -> Value? {
        if Self.exactBinarySelectors.contains(selector) {
            let other = arguments[0]
            if case .float = other {
                return try floatPrimitive(finiteDouble(decimal.doubleValue), selector, arguments)
            }
            if case .fraction(let fraction) = other {
                return try fractionBinary(fractionFromDecimal(decimal), selector, fraction)
            }
            return try scaledDecimalBinary(decimal, selector, decimalOperand(other))
        }
        let coefficient = decimal.coefficient
        switch selector {
        case "scale": return .integer(Int64(decimal.scale))
        case "negated": return .scaledDecimal(try ScaledDecimal(-coefficient, scale: decimal.scale))
        case "abs": return .scaledDecimal(try ScaledDecimal(coefficient.magnitude, scale: decimal.scale))
        case "squared": return try scaledDecimalBinary(decimal, "*", decimal)
        case "reciprocal": return try scaledDecimalBinary(ScaledDecimal(.one, scale: 0), "/", decimal)
        case "negative": return .boolean(coefficient.isNegative)
        case "positive": return .boolean(!coefficient.isNegative)
        case "strictlyPositive": return .boolean(!coefficient.isZero && !coefficient.isNegative)
        case "sign": return .integer(coefficient.isZero ? 0 : coefficient.isNegative ? -1 : 1)
        case "asFloat", "asFloatE", "asFloatD", "asFloatQ": return try finiteFloat(decimal.doubleValue)
        case "asScaledDecimal:": return try convertToScaledDecimal(.scaledDecimal(decimal), scale: arguments[0])
        case "asFraction": return try fractionValue(coefficient, decimalFactor(decimal.scale))
        case "floor": return integerValue(try floorDivision(coefficient, by: decimalFactor(decimal.scale)).quotient)
        case "rounded", "asInteger": return integerValue(try roundedQuotient(coefficient, by: decimalFactor(decimal.scale)))
        case "integerPart", "fractionPart":
            let factor = try decimalFactor(decimal.scale)
            let parts = try floorDivision(coefficient, by: factor)
            let part = selector == "integerPart"
                ? try parts.quotient.multiplied(by: factor, charge: chargeNumericWork)
                : parts.remainder
            return .scaledDecimal(try ScaledDecimal(part, scale: decimal.scale))
        case "truncated", "ceiling":
            let result = try coefficient.divided(by: decimalFactor(decimal.scale), charge: chargeNumericWork)
            if selector == "ceiling" && !coefficient.isNegative && !result.remainder.isZero {
                return integerValue(result.quotient + .one)
            }
            return integerValue(result.quotient)
        default: return nil
        }
    }

    private func decimalOperand(_ number: Value) throws -> ScaledDecimal {
        if case .scaledDecimal(let decimal) = number { return decimal }
        return try ScaledDecimal(unboundedInteger(number), scale: 0)
    }

    func fractionFromDecimal(_ number: ScaledDecimal) throws -> ExactFraction {
        try ExactFraction(number.coefficient, decimalFactor(number.scale), charge: chargeNumericWork)
    }

    func equalScaledDecimal(_ number: ScaledDecimal, other: Value, identity: Bool) throws -> Bool {
        switch other {
        case .float(let float): return !identity && number.doubleValue == float
        case .fraction(let fraction):
            guard !identity else { return false }
            let converted = try fractionFromDecimal(number)
            try chargeNumericWork(max(converted.numerator.wordCount, fraction.numerator.wordCount)
                                  + max(converted.denominator.wordCount, fraction.denominator.wordCount))
            return converted == fraction
        case .scaledDecimal, .integer, .largeInteger:
            if identity {
                guard case .scaledDecimal(let other) = other, number.scale == other.scale else { return false }
            }
            let (left, right, _) = try alignedDecimals(number, decimalOperand(other))
            return left == right
        default:
            return false
        }
    }

    func scaledDecimalBinary(_ lhs: ScaledDecimal, _ selector: String, _ rhs: ScaledDecimal) throws -> Value {
        if selector == "*" {
            let scale = lhs.scale + rhs.scale
            let coefficient = try lhs.coefficient.multiplied(by: rhs.coefficient, charge: chargeNumericWork)
            if scale <= ScaledDecimal.maximumScale { return .scaledDecimal(try ScaledDecimal(coefficient, scale: scale)) }
            let excessPlaces = try decimalFactor(scale - ScaledDecimal.maximumScale)
            let reduced = try coefficient.divided(by: excessPlaces, charge: chargeNumericWork)
            guard reduced.remainder.isZero else { throw SmalltalkError("Scaled decimal multiplication exceeds the supported scale.") }
            return .scaledDecimal(try ScaledDecimal(reduced.quotient, scale: ScaledDecimal.maximumScale))
        }
        let (left, right, scale) = try alignedDecimals(lhs, rhs)
        switch selector {
        case "+": return .scaledDecimal(try ScaledDecimal(left + right, scale: scale))
        case "-": return .scaledDecimal(try ScaledDecimal(left - right, scale: scale))
        case "/":
            let ratio = try ExactFraction(left, right, charge: chargeNumericWork)
            let exactScale = try terminatingScale(of: ratio.denominator)
            let resultScale = max(scale, exactScale ?? ScaledDecimal.repeatingDivisionScale)
            return try scaledQuotient(ratio.numerator, by: ratio.denominator, scale: resultScale)
        case "//": return integerValue(try floorDivision(left, by: right).quotient)
        case "\\\\":
            return .scaledDecimal(try ScaledDecimal(floorDivision(left, by: right).remainder, scale: scale))
        case "<": return .boolean(left < right)
        case ">": return .boolean(left > right)
        case "<=": return .boolean(left <= right)
        case ">=": return .boolean(left >= right)
        default: throw SmalltalkError("Unsupported scaled decimal operation.")
        }
    }

    private func alignedDecimals(_ lhs: ScaledDecimal, _ rhs: ScaledDecimal) throws -> (BigInteger, BigInteger, Int) {
        let scale = max(lhs.scale, rhs.scale)
        let left = try shiftDecimal(lhs.coefficient, by: scale - lhs.scale)
        let right = try shiftDecimal(rhs.coefficient, by: scale - rhs.scale)
        try chargeNumericWork(max(left.wordCount, right.wordCount))
        return (left, right, scale)
    }

    private func decimalFactor(_ exponent: Int) throws -> BigInteger {
        if exponent == 0 { return .one }
        let width = exponent / 8 + 1
        try chargeNumericWork(width * width)
        return .powerOfTen(exponent)
    }

    private func shiftDecimal(_ coefficient: BigInteger, by exponent: Int) throws -> BigInteger {
        if exponent == 0 || coefficient.isZero { return coefficient }
        return try coefficient.multiplied(by: decimalFactor(exponent), charge: chargeNumericWork)
    }

    private func roundedQuotient(_ value: BigInteger, by divisor: BigInteger) throws -> BigInteger {
        let (quotient, remainder) = try value.divided(by: divisor, charge: chargeNumericWork)
        if remainder.magnitude + remainder.magnitude < divisor.magnitude { return quotient }
        return value.isNegative == divisor.isNegative ? quotient + .one : quotient - .one
    }

    private func scaledQuotient(_ value: BigInteger, by divisor: BigInteger, scale: Int) throws -> Value {
        let coefficient = try roundedQuotient(shiftDecimal(value, by: scale), by: divisor)
        return .scaledDecimal(try ScaledDecimal(coefficient, scale: scale))
    }

    // A reduced rational terminates in base 10 exactly when its denominator
    // divides a power of ten. The required scale is max(power of 2, power of 5).
    private func terminatingScale(of denominator: BigInteger) throws -> Int? {
        var remaining = denominator
        var scale = 0
        for factor in [BigInteger(2), BigInteger(5)] {
            var count = 0
            while remaining != .one {
                let division = try remaining.divided(by: factor, charge: chargeNumericWork)
                if !division.remainder.isZero { break }
                remaining = division.quotient
                count += 1
                if count > ScaledDecimal.maximumScale { return nil }
            }
            scale = max(scale, count)
        }
        return remaining == .one ? scale : nil
    }
}
