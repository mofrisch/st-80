import Foundation

/// An immutable reduced fraction with a positive denominator. A reference keeps
/// the pair of integers out of the VM's operand slots and recursive call frames.
final class ExactFraction: Codable, Sendable, Equatable {
    let numerator: BigInteger
    let denominator: BigInteger

    init(_ numerator: BigInteger, _ denominator: BigInteger, charge: (Int) throws -> Void) throws {
        guard !denominator.isZero else { throw SmalltalkError("Division by zero.") }
        if denominator.magnitude == .one || numerator.isZero {
            self.numerator = denominator.isNegative ? -numerator : numerator
            self.denominator = .one
            return
        }

        var previous = numerator.magnitude
        var divisor = denominator.magnitude
        while !divisor.isZero && divisor != .one {
            let (_, remainder) = try previous.divided(by: divisor, charge: charge)
            previous = divisor
            divisor = remainder
        }
        let signed = denominator.isNegative ? -numerator : numerator
        if divisor == .one {
            self.numerator = signed
            self.denominator = denominator.magnitude
        } else {
            self.numerator = try signed.divided(by: previous, charge: charge).quotient
            self.denominator = try denominator.magnitude.divided(by: previous, charge: charge).quotient
        }
    }

    convenience init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let top = try container.decode(BigInteger.self, forKey: .numerator)
        let bottom = try container.decode(BigInteger.self, forKey: .denominator)
        guard !bottom.isZero, !bottom.isNegative else {
            throw DecodingError.dataCorruptedError(forKey: .denominator, in: container,
                                                   debugDescription: "A fraction requires a positive denominator.")
        }
        var remaining = SmalltalkRuntime.executionStepLimit
        try self.init(top, bottom) { words in
            remaining -= SmalltalkRuntime.numericWorkSteps(words)
            guard remaining >= 0 else { throw SmalltalkError("Fraction in image exceeds the arithmetic budget.") }
        }
        guard numerator == top, denominator == bottom else {
            throw DecodingError.dataCorruptedError(forKey: .denominator, in: container,
                                                   debugDescription: "A stored fraction must already be reduced.")
        }
    }

    static func == (lhs: ExactFraction, rhs: ExactFraction) -> Bool {
        lhs.numerator == rhs.numerator && lhs.denominator == rhs.denominator
    }

    var doubleValue: Double {
        let top = numerator.floatingComponents
        let bottom = denominator.floatingComponents
        return Double(sign: top.coefficient.sign, exponent: top.exponent - bottom.exponent,
                      significand: (top.coefficient / bottom.coefficient).magnitude)
    }
}
