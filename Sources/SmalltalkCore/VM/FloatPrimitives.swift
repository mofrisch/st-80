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
        case .fraction(let number): return try finiteDouble(number.doubleValue)
        case .float(let number): return number
        default: throw SmalltalkError("Expected a number.")
        }
    }

    func floatPrimitive(_ number: Double, _ selector: String, _ arguments: [Value]) throws -> Value? {
        switch selector {
        case "+": return try finiteFloat(number + floatingNumber(arguments[0]))
        case "-": return try finiteFloat(number - floatingNumber(arguments[0]))
        case "*": return try finiteFloat(number * floatingNumber(arguments[0]))
        case "/", "//", "\\\\":
            let divisor = try floatingNumber(arguments[0])
            guard divisor != 0 else { throw SmalltalkError("Division by zero.") }
            if selector == "/" { return try finiteFloat(number / divisor) }
            if selector == "//" {
                guard let quotient = BigInteger(exactly: (number / divisor).rounded(.down)) else {
                    throw SmalltalkError("Floating-point quotient is outside the supported range.")
                }
                return integerValue(quotient)
            }
            let remainder = number.truncatingRemainder(dividingBy: divisor)
            return .float(remainder != 0 && remainder.sign != divisor.sign ? remainder + divisor : remainder)
        case "<": return .boolean(try number < floatingNumber(arguments[0]))
        case ">": return .boolean(try number > floatingNumber(arguments[0]))
        case "<=": return .boolean(try number <= floatingNumber(arguments[0]))
        case ">=": return .boolean(try number >= floatingNumber(arguments[0]))
        case "negated": return .float(-number)
        case "abs": return .float(abs(number))
        case "squared": return try finiteFloat(number * number)
        case "asFloat", "asFloatE", "asFloatD", "asFloatQ": return .float(number)
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
        case "raisedTo:": return try finiteFloat(pow(number, floatingNumber(arguments[0])))
        case "sin": return try finiteFloat(sin(number))
        case "cos": return try finiteFloat(cos(number))
        case "tan": return try finiteFloat(tan(number))
        default: return nil
        }
    }
}
