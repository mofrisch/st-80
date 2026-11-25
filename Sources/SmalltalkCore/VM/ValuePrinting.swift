/// Bounded diagnostic output for results, errors, printString and bindings.
/// Depth and collection prefixes describe the representation; these shared
/// budgets also bound expansion of repeated references and large string leaves.
struct ValuePrinter {
    static let maximumBytes = 65_536
    static let maximumValues = 4_096
    static let bindingBytes = 4_096
    static let allBindingsBytes = 65_536
    static let allBindingsValues = 8_192

    private let byteLimit: Int
    private(set) var remainingValues: Int
    private var output = ""
    private var outputBytes = 0
    private var truncated = false

    init(maximumBytes: Int = Self.maximumBytes, maximumValues: Int = Self.maximumValues) {
        byteLimit = max(0, maximumBytes)
        remainingValues = max(0, maximumValues)
        output.reserveCapacity(min(byteLimit, 4_096))
    }

    mutating func print(_ value: Value, depth: Int = 0) -> String {
        appendValue(value, depth: depth)
        return output
    }

    private mutating func appendValue(_ value: Value, depth: Int) {
        guard !truncated else { return }
        guard remainingValues > 0 else { truncate(); return }
        remainingValues -= 1
        guard depth < 5 else { append("…"); return }
        switch value {
        case .integer(let number): append(String(number))
        case .string(let text):
            append("'")
            // Escape as we append. Replacing every quote first would allocate
            // the entire escaped input even when only a short prefix fits.
            for scalar in text.unicodeScalars {
                guard !truncated else { return }
                append(scalar)
                if scalar == "'" { append(scalar) }
            }
            append("'")
        case .symbol(let name): append("#"); append(name)
        case .boolean(let value): append(value ? "true" : "false")
        case .nilValue: append("nil")
        case .classObject(let stClass): append(stClass.name)
        case .object(let object):
            append("a "); append(object.stClass.name)
            let fields = object.stClass.fields.prefix(8)
            guard !fields.isEmpty else { return }
            append(" (")
            for (index, name) in fields.enumerated() {
                guard !truncated else { return }
                if index > 0 { append(", ") }
                append(name); append(": ")
                appendValue(object.fields[name] ?? .nilValue, depth: depth + 1)
            }
            append(")")
        case .array(let array):
            append("#(")
            for (index, element) in array.elements.prefix(32).enumerated() {
                guard !truncated else { return }
                if index > 0 { append(" ") }
                appendValue(element, depth: depth + 1)
            }
            if array.elements.count > 32 { append(" …") }
            append(")")
        case .block(let block): append("[Block · \(block.parameters.count) arguments]")
        case .transcript: append("Transcript")
        }
    }

    private mutating func append(_ text: String) {
        for scalar in text.unicodeScalars {
            guard !truncated else { return }
            append(scalar)
        }
    }

    private mutating func append(_ scalar: Unicode.Scalar) {
        guard !truncated else { return }
        let bytes = scalar.utf8.count
        guard bytes <= byteLimit - outputBytes else { truncate(); return }
        output.unicodeScalars.append(scalar)
        outputBytes += bytes
    }

    private mutating func truncate() {
        guard !truncated else { return }
        truncated = true
        guard byteLimit >= 3 else { output = ""; outputBytes = 0; return }
        // Scalar iteration never reads an unbounded grapheme from the input.
        // Discard the final grapheme of our bounded prefix because it may be
        // only the beginning of a composed character or emoji sequence.
        if let last = output.popLast() { outputBytes -= last.utf8.count }
        while outputBytes + 3 > byteLimit {
            let last = output.removeLast()
            outputBytes -= last.utf8.count
        }
        output += "…"
        outputBytes += 3
    }
}

extension SmalltalkRuntime {
    func printValue(_ value: Value, depth: Int = 0) -> String {
        var printer = ValuePrinter()
        return printer.print(value, depth: depth)
    }
}
