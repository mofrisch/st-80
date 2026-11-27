/// Selector identity follows the image's character sequence, even when Swift
/// considers two spellings canonically equivalent.
struct SelectorKey: Hashable, Sendable {
    let spelling: String

    init(_ spelling: String) { self.spelling = spelling }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.spelling.utf8.elementsEqual(rhs.spelling.utf8)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(spelling)
        hasher.combine(spelling.utf8.count)
    }
}

struct SelectorMap<EntryValue>: Sequence, ExpressibleByDictionaryLiteral {
    private var storage: [SelectorKey: EntryValue] = [:]

    init(dictionaryLiteral elements: (String, EntryValue)...) {
        for (key, value) in elements { self[key] = value }
    }

    var isEmpty: Bool { storage.isEmpty }
    var count: Int { storage.count }
    var keys: [String] { storage.keys.map(\.spelling) }
    var selectorKeys: Set<SelectorKey> { Set(storage.keys) }
    var values: Dictionary<SelectorKey, EntryValue>.Values { storage.values }

    subscript(selector: String) -> EntryValue? {
        get { storage[SelectorKey(selector)] }
        set { storage[SelectorKey(selector)] = newValue }
    }

    mutating func updateValue(_ value: EntryValue, forKey selector: String) -> EntryValue? {
        storage.updateValue(value, forKey: SelectorKey(selector))
    }

    @discardableResult
    mutating func removeValue(forKey selector: String) -> EntryValue? {
        storage.removeValue(forKey: SelectorKey(selector))
    }

    func mapValues<T>(_ transform: (EntryValue) throws -> T) rethrows -> SelectorMap<T> {
        var result: SelectorMap<T> = [:]
        result.storage = try storage.mapValues(transform)
        return result
    }

    func makeIterator() -> AnyIterator<(key: String, value: EntryValue)> {
        var iterator = storage.makeIterator()
        return AnyIterator { iterator.next().map { ($0.key.spelling, $0.value) } }
    }
}

extension SelectorMap: Sendable where EntryValue: Sendable {}

extension SelectorMap: Codable where EntryValue: Codable {
    private struct Record: Codable {
        let selector: String
        let value: EntryValue
    }

    init(from decoder: any Decoder) throws {
        if var records = try? decoder.unkeyedContainer() {
            while !records.isAtEnd {
                let record = try records.decode(Record.self)
                guard updateValue(record.value, forKey: record.selector) == nil else {
                    throw DecodingError.dataCorruptedError(in: records, debugDescription: "Duplicate method selector.")
                }
            }
        } else {
            for (selector, value) in try [String: EntryValue](from: decoder) { self[selector] = value }
        }
    }

    func encode(to encoder: any Encoder) throws {
        // Preserve the keyed archive format whenever String keys can represent
        // the whole table. Explicit records keep colliding spellings distinct.
        var keyed: [String: EntryValue] = [:]
        keyed.reserveCapacity(count)
        for (selector, value) in self { keyed[selector] = value }
        if keyed.count == count {
            try keyed.encode(to: encoder)
        } else {
            var records = encoder.unkeyedContainer()
            for (selector, value) in sorted(by: { $0.key.utf8.lexicographicallyPrecedes($1.key.utf8) }) {
                try records.encode(Record(selector: selector, value: value))
            }
        }
    }
}
