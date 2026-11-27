/// Smalltalk names follow the image's character sequence, even when Swift
/// considers two spellings canonically equivalent.
struct IdentifierKey: Hashable, Sendable {
    let spelling: String

    init(_ spelling: String) { self.spelling = spelling }

    func matches(_ name: String) -> Bool { self == Self(name) }

    static func set(_ names: some Sequence<String>) -> Set<Self> {
        Set(names.map(Self.init))
    }

    static func precedes(_ lhs: String, _ rhs: String) -> Bool {
        lhs.utf8.lexicographicallyPrecedes(rhs.utf8)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.spelling.utf8.elementsEqual(rhs.spelling.utf8)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(spelling)
        hasher.combine(spelling.utf8.count)
    }
}

typealias SelectorKey = IdentifierKey
typealias SelectorMap<Value> = IdentifierMap<Value>

struct IdentifierMap<EntryValue>: Sequence, ExpressibleByDictionaryLiteral {
    private var storage: [IdentifierKey: EntryValue] = [:]

    init(dictionaryLiteral elements: (String, EntryValue)...) {
        self.init(uniqueKeysWithValues: elements)
    }

    init(uniqueKeysWithValues elements: some Sequence<(String, EntryValue)>) {
        for (key, value) in elements { self[key] = value }
    }

    var isEmpty: Bool { storage.isEmpty }
    var count: Int { storage.count }
    var keys: [String] { storage.keys.map(\.spelling) }
    var identifierKeys: Set<IdentifierKey> { Set(storage.keys) }
    var values: Dictionary<IdentifierKey, EntryValue>.Values { storage.values }

    subscript(name: String) -> EntryValue? {
        get { storage[IdentifierKey(name)] }
        set { storage[IdentifierKey(name)] = newValue }
    }

    subscript(name: String, default defaultValue: @autoclosure () -> EntryValue) -> EntryValue {
        get { storage[IdentifierKey(name), default: defaultValue()] }
        _modify { yield &storage[IdentifierKey(name), default: defaultValue()] }
    }

    mutating func updateValue(_ value: EntryValue, forKey name: String) -> EntryValue? {
        storage.updateValue(value, forKey: IdentifierKey(name))
    }

    @discardableResult
    mutating func removeValue(forKey name: String) -> EntryValue? {
        storage.removeValue(forKey: IdentifierKey(name))
    }

    mutating func removeAll() { storage.removeAll() }

    func mapValues<T>(_ transform: (EntryValue) throws -> T) rethrows -> IdentifierMap<T> {
        var result: IdentifierMap<T> = [:]
        result.storage = try storage.mapValues(transform)
        return result
    }

    func makeIterator() -> AnyIterator<(key: String, value: EntryValue)> {
        var iterator = storage.makeIterator()
        return AnyIterator { iterator.next().map { ($0.key.spelling, $0.value) } }
    }
}

extension IdentifierMap: Sendable where EntryValue: Sendable {}

extension IdentifierMap: Codable where EntryValue: Codable {
    private struct Record: Codable {
        let name: String
        let value: EntryValue

        // This key first shipped in the executable method table.
        enum CodingKeys: String, CodingKey { case name = "selector", value }
    }

    init(from decoder: any Decoder) throws {
        if var records = try? decoder.unkeyedContainer() {
            while !records.isAtEnd {
                let record = try records.decode(Record.self)
                guard updateValue(record.value, forKey: record.name) == nil else {
                    throw DecodingError.dataCorruptedError(in: records, debugDescription: "Duplicate identifier.")
                }
            }
        } else {
            for (name, value) in try [String: EntryValue](from: decoder) { self[name] = value }
        }
    }

    func encode(to encoder: any Encoder) throws {
        // Preserve the keyed archive format whenever String keys can represent
        // the whole table. Explicit records keep colliding spellings distinct.
        var keyed: [String: EntryValue] = [:]
        keyed.reserveCapacity(count)
        for (name, value) in self { keyed[name] = value }
        if keyed.count == count {
            try keyed.encode(to: encoder)
        } else {
            var records = encoder.unkeyedContainer()
            for (name, value) in sorted(by: { IdentifierKey.precedes($0.key, $1.key) }) {
                try records.encode(Record(name: name, value: value))
            }
        }
    }
}
