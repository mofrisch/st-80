import BigInt

/// Adapts BigInt to the VM's arithmetic budget and the existing image encoding.
/// An immutable reference keeps BigInt's storage out of recursive VM frames.
final class BigInteger: Codable, Sendable, Comparable, CustomStringConvertible {
    private static let decimalBase: BigUInt = 1_000_000_000
    private let value: BigInt

    static let zero = BigInteger(0)
    static let one = BigInteger(1)

    init(_ value: Int64) {
        self.value = BigInt(value)
    }

    private init(value: BigInt) {
        self.value = value
    }

    init?(exactly value: Double) {
        guard let integer = BigInt(exactly: value) else { return nil }
        self.value = integer
    }

    // Images continue to use the original little-endian base-10^9 words.
    private enum CodingKeys: String, CodingKey { case negative, words }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let negative = try container.decode(Bool.self, forKey: .negative)
        let words = try container.decode([UInt32].self, forKey: .words)
        guard words.last != 0, !negative || !words.isEmpty, words.allSatisfy({ $0 < 1_000_000_000 }) else {
            throw DecodingError.dataCorruptedError(forKey: .words, in: container, debugDescription: "Invalid integer magnitude.")
        }
        value = BigInt(sign: negative ? .minus : .plus, magnitude: Self.decodeDecimalWords(words))
    }

    func encode(to encoder: any Encoder) throws {
        var words: [UInt32] = []
        visitDecimalWords { word, _ in
            words.append(word)
            return true
        }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isNegative, forKey: .negative)
        try container.encode(Array(words.reversed()), forKey: .words)
    }

    static func parseMagnitude(_ text: String, radix: Int, charge: (Int) throws -> Void) throws -> BigInteger? {
        guard (2...36).contains(radix), !text.isEmpty else { return nil }
        try charge(text.utf8.count)
        let significant = text.drop(while: { $0 == "0" })
        guard !significant.isEmpty else { return .zero }
        let bitsPerDigit = Int.bitWidth - (radix - 1).leadingZeroBitCount
        let bits = workProduct(significant.utf8.count, bitsPerDigit)
        let width = (bits - 1) / UInt.bitWidth + 1
        // The dependency can pack digits directly only when a complete
        // group of digits fills a machine word.
        if radix.nonzeroBitCount != 1 || UInt.bitWidth % bitsPerDigit != 0 {
            try charge(workProduct(width, width))
        }

        let magnitude: BigUInt?
        if radix < 36 {
            guard significant.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) }) else { return nil }
            magnitude = BigUInt(significant, radix: radix)
        } else {
            // BigInt 6.0.1 limits its string initializer to radices below 36.
            // Swift's fixed-width constructor can parse each radix-36 group.
            var result: BigUInt = 0
            var rest = significant
            let digitsPerWord = (UInt.bitWidth - 1) / 6
            var width = rest.utf8.count % digitsPerWord
            if width == 0 { width = digitsPerWord }
            while !rest.isEmpty {
                let group = rest.prefix(width)
                guard group.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) }),
                      let digits = UInt(group, radix: 36) else { return nil }
                let scale = (0..<width).reduce(UInt(1)) { power, _ in power * 36 }
                result.multiply(byWord: scale)
                result += BigUInt(digits)
                rest = rest.dropFirst(width)
                width = digitsPerWord
            }
            magnitude = result
        }
        return magnitude.map { BigInteger(value: BigInt(sign: .plus, magnitude: $0)) }
    }

    // A conservative estimate in the VM's existing ~30-bit work units.
    var wordCount: Int {
        let bits = value.magnitude.bitWidth
        return bits == 0 ? 0 : (bits - 1) / 29 + 1
    }
    var isZero: Bool { value.isZero }
    var isNegative: Bool { value.sign == .minus }
    var magnitude: BigInteger {
        if !isNegative { return self }
        return -self
    }
    var int64: Int64? { Int64(exactly: value) }
    var bitWidth: Int { value.magnitude.bitWidth }

    static func powerOfTen(_ exponent: Int) -> BigInteger { BigInteger(value: BigInt(10).power(exponent)) }
    func shiftedLeft(_ count: Int) -> BigInteger { BigInteger(value: value << count) }
    func shiftedRight(_ count: Int) -> BigInteger { BigInteger(value: value >> count) }

    func bitAnd(_ other: BigInteger) -> BigInteger { BigInteger(value: value & other.value) }
    func bitOr(_ other: BigInteger) -> BigInteger { BigInteger(value: value | other.value) }
    func bitXor(_ other: BigInteger) -> BigInteger { BigInteger(value: value ^ other.value) }

    func radixString(_ radix: Int, charge: (Int) throws -> Void) throws -> String {
        try charge(radix.nonzeroBitCount == 1 ? wordCount : Self.workProduct(wordCount, wordCount))
        return String(value, radix: radix, uppercase: true)
    }

    var description: String {
        var text = ""
        describe { fragment in
            text += fragment
            return true
        }
        return text
    }

    var doubleValue: Double {
        if let small = int64 { return Double(small) }
        let overflow = isNegative ? -Double.infinity : Double.infinity
        if value.magnitude.bitWidth > 1_024 { return overflow }
        return Double(String(value)) ?? overflow
    }

    /// Round an exact ratio once, including ties and subnormals, before converting it to binary64.
    func doubleValue(dividedBy denominator: BigInteger, charge: (Int) throws -> Void) throws -> Double {
        let sign: FloatingPointSign = isNegative ? .minus : .plus
        if isZero { return 0 }
        let top = value.magnitude
        let bottom = denominator.value.magnitude
        var exponent = top.bitWidth - bottom.bitWidth
        if exponent > 1_024 { return isNegative ? -.infinity : .infinity }
        if exponent < -1_075 { return isNegative ? -0.0 : 0.0 }
        try charge(Self.workProduct(max(wordCount, denominator.wordCount), 4))
        if exponent >= 0 ? top < (bottom << exponent) : (top << -exponent) < bottom { exponent -= 1 }

        let unit = max(exponent - Double.significandBitCount, -1_074)
        let divisor = bottom << max(0, unit)
        let quotient = (top << max(0, -unit)).quotientAndRemainder(dividingBy: divisor)
        var significand = UInt64(quotient.quotient)
        let remainderTimesTwo = quotient.remainder << 1
        if remainderTimesTwo > divisor || remainderTimesTwo == divisor && significand & 1 == 1 { significand += 1 }
        return Double(sign: sign, exponent: unit, significand: Double(significand))
    }

    func roundedSquareRoot(charge: (Int) throws -> Void) throws -> BigInteger {
        guard !isNegative else { throw SmalltalkError("Square root requires a nonnegative integer.") }
        if isZero { return self }
        // The dependency uses Newton's method, doubling significant bits on each iteration.
        let iterations = Int.bitWidth - bitWidth.leadingZeroBitCount + 2
        try charge(Self.workProduct(Self.workProduct(wordCount, wordCount), iterations))
        let magnitude = value.magnitude
        let root = magnitude.squareRoot()
        // The midpoint squared is root² + root + 1/4.
        let rounded = magnitude - root * root > root ? root + 1 : root
        return BigInteger(value: BigInt(rounded))
    }

    func squareRoot(dividedBy denominator: BigInteger, charge: (Int) throws -> Void) throws -> Double {
        guard !isNegative else { throw SmalltalkError("Square root requires a nonnegative number.") }
        if isZero { return 0 }
        let top = value.magnitude
        let bottom = denominator.value.magnitude
        var exponent = top.bitWidth - bottom.bitWidth
        if exponent > 2_048 { return .infinity }
        if exponent < -2_150 { return 0 }
        try charge(Self.workProduct(max(wordCount, denominator.wordCount), 4))
        if exponent >= 0 ? top < (bottom << exponent) : (top << -exponent) < bottom { exponent -= 1 }
        if exponent > 2_047 { return .infinity }
        if exponent < -2_150 { return 0 }

        let unit = max((exponent >> 1) - Double.significandBitCount, -1_074)
        let dividend = top << max(0, -2 * unit)
        let divisor = bottom << max(0, 2 * unit)
        try charge(Self.workProduct(dividend.words.count, divisor.words.count))
        var significand = (dividend / divisor).squareRoot()
        // Square the rounding midpoint to compare it with the original radicand.
        let midpoint = (significand << 1) + 1
        let threshold = midpoint * midpoint * divisor
        let fourTimesDividend = dividend << 2
        if fourTimesDividend > threshold || fourTimesDividend == threshold && significand[bitAt: 0] {
            significand += 1
        }
        return Double(sign: .plus, exponent: unit, significand: Double(UInt64(significand)))
    }

    /// Allows the diagnostic printer to stop without formatting the tail.
    func describe(decimalPlaces: Int = 0, _ append: (String) -> Bool) {
        if isZero {
            if append("0"), decimalPlaces > 0 { _ = append("." + String(repeating: "0", count: decimalPlaces)) }
            return
        }
        if isNegative && !append("-") { return }
        var first = true
        visitDecimalWords { word, remainingWords in
            let digits = String(word)
            let chunk = first ? digits : String(repeating: "0", count: 9 - digits.count) + digits
            let digitsAfter = remainingWords * 9
            let point = chunk.count + digitsAfter - decimalPlaces
            if first && point <= 0 {
                guard append("0." + String(repeating: "0", count: -point)) else { return false }
            }
            first = false
            if decimalPlaces > 0 && decimalPlaces >= digitsAfter && point > 0 && point <= chunk.count {
                return append(String(chunk.prefix(point))) && append(".") && append(String(chunk.dropFirst(point)))
            }
            return append(chunk)
        }
    }

    static prefix func - (operand: BigInteger) -> BigInteger { BigInteger(value: -operand.value) }
    static func == (lhs: BigInteger, rhs: BigInteger) -> Bool { lhs.value == rhs.value }
    static func < (lhs: BigInteger, rhs: BigInteger) -> Bool { lhs.value < rhs.value }
    static func + (lhs: BigInteger, rhs: BigInteger) -> BigInteger { BigInteger(value: lhs.value + rhs.value) }
    static func - (lhs: BigInteger, rhs: BigInteger) -> BigInteger { BigInteger(value: lhs.value - rhs.value) }

    func multiplied(by other: BigInteger, charge: (Int) throws -> Void) throws -> BigInteger {
        guard !isZero, !other.isZero else { return .zero }
        // Reserve work before entering a synchronous library operation.
        try charge(Self.workProduct(wordCount, other.wordCount))
        return BigInteger(value: value * other.value)
    }

    /// Truncates toward zero, with a remainder having the sign of the dividend.
    func divided(by divisor: BigInteger, charge: (Int) throws -> Void) throws -> (quotient: BigInteger, remainder: BigInteger) {
        guard !divisor.isZero else { throw SmalltalkError("Division by zero.") }
        try charge(max(wordCount, divisor.wordCount))
        if value.magnitude < divisor.value.magnitude { return (.zero, self) }
        try charge(Self.workProduct(wordCount, divisor.wordCount))
        let division = value.magnitude.quotientAndRemainder(dividingBy: divisor.value.magnitude)
        let quotient = BigInt(sign: value.sign == divisor.value.sign ? .plus : .minus, magnitude: division.quotient)
        let remainder = BigInt(sign: value.sign, magnitude: division.remainder)
        return (BigInteger(value: quotient), BigInteger(value: remainder))
    }

    private static func workProduct(_ lhs: Int, _ rhs: Int) -> Int {
        let result = lhs.multipliedReportingOverflow(by: rhs)
        return result.overflow ? .max : result.partialValue
    }

    private static func decodeDecimalWords(_ words: [UInt32]) -> BigUInt {
        guard !words.isEmpty else { return 0 }
        var powers = [decimalBase]
        var capacity = 2
        while capacity < words.count {
            let power = powers[powers.count - 1]
            powers.append(power * power)
            capacity *= 2
        }
        // Split at powers of two so conversion of a wide image value does
        // not multiply a growing magnitude by a single word on every pass.
        func combine(_ groups: ArraySlice<UInt32>, level: Int) -> BigUInt {
            guard let first = groups.first else { return 0 }
            guard groups.count > 1 else { return BigUInt(first) }
            let half = 1 << (level - 1)
            if groups.count <= half { return combine(groups, level: level - 1) }
            let middle = groups.startIndex + half
            return combine(groups[middle...], level: level - 1) * powers[level - 1]
                + combine(groups[..<middle], level: level - 1)
        }
        return combine(words[...], level: powers.count)
    }

    // The callback sees most significant words first, with their offsets from the end.
    private func visitDecimalWords(_ append: (UInt32, Int) -> Bool) {
        guard !isZero else { return }
        let magnitude = value.magnitude
        var powers = [Self.decimalBase]
        while let power = powers.last, power <= magnitude { powers.append(power * power) }
        func visit(_ group: BigUInt, level: Int, padded: Bool, remaining: Int) -> Bool {
            if level == 0 { return append(UInt32(truncatingIfNeeded: group), remaining) }
            let factor = powers[level - 1]
            let half = 1 << (level - 1)
            if group < factor {
                if padded {
                    for index in (half..<(2 * half)).reversed() {
                        guard append(0, remaining + index) else { return false }
                    }
                }
                return visit(group, level: level - 1, padded: padded, remaining: remaining)
            }
            let division = group.quotientAndRemainder(dividingBy: factor)
            return visit(division.quotient, level: level - 1, padded: padded, remaining: remaining + half)
                && visit(division.remainder, level: level - 1, padded: true, remaining: remaining)
        }
        _ = visit(magnitude, level: powers.count - 1, padded: false, remaining: 0)
    }
}
