import Darwin
import Foundation

public struct ChangeInfo: Identifiable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable { case classDefinition, method }
    public let id: String
    public let sequence: Int64
    public let timestamp: Date
    public let kind: Kind
    public let className: String
    public let selector: String?
    public let superclass: String?
    public let fields: [String]?
    public let source: String
    var methodSide: MethodSide?
    public var side: MethodSide { methodSide ?? .instance }
}

/// Append before installing accepted code. Each complete JSON line is an
/// independently recoverable record; an interrupted final write is ignored.
final class SourceJournal {
    struct Header: Codable { var format = "st80-changes"; var version = 1; let id: String }
    static let maxBytes = 64 * 1024 * 1024
    let id: String
    private(set) var records: [ChangeInfo]
    private(set) var url: URL?
    private var physicalSize: UInt64 = 0
    private var validSize: UInt64 = 0
    private var memoryBytes: Int = 0
    var savedSequence: Int64 = 0
    var sequence: Int64 { records.last?.sequence ?? 0 }

    init(id: String = UUID().uuidString, records: [ChangeInfo] = []) {
        self.id = id; self.records = records
        memoryBytes = records.reduce(0) { $0 + $1.source.utf8.count }
    }
    private static func line<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        var data = try encoder.encode(value); data.append(10); return data
    }
    func data() throws -> Data {
        var data = try Self.line(Header(id: id))
        for record in records { data.append(try Self.line(record)) }
        guard data.count <= Self.maxBytes else { throw SmalltalkError("The changes log exceeds the 64 MiB limit.") }
        return data
    }
    func attach(to url: URL) throws {
        guard url.isFileURL else { throw SmalltalkError("Changes logs must be saved locally.") }
        guard !FileManager.default.fileExists(atPath: url.path) else { throw SmalltalkError("Changes log \(url.lastPathComponent) already exists. Choose a different image name.") }
        let bytes = try data()
        try Self.createFile(bytes, at: url)
        self.url = url; physicalSize = UInt64(bytes.count); validSize = physicalSize
    }
    @discardableResult
    func append(kind: ChangeInfo.Kind, className: String, selector: String? = nil, superclass: String? = nil, fields: [String]? = nil, side: MethodSide = .instance, source: String) throws -> ChangeInfo {
        guard records.count < 100_000 else { throw SmalltalkError("The changes log contains too many entries.") }
        let record = ChangeInfo(id: UUID().uuidString, sequence: sequence + 1, timestamp: Date(), kind: kind, className: className, selector: selector, superclass: superclass, fields: fields, source: source, methodSide: side == .classSide ? side : nil)
        let bytes = try Self.line(record)
        guard validSize + UInt64(bytes.count) <= Self.maxBytes, memoryBytes + bytes.count <= Self.maxBytes else { throw SmalltalkError("The changes log exceeds the 64 MiB limit.") }
        if let url {
            let file = try FileHandle(forUpdating: url)
            defer { try? file.close() }
            guard flock(file.fileDescriptor, LOCK_EX | LOCK_NB) == 0 else { throw SmalltalkError("Another session is writing to the changes log.") }
            defer { flock(file.fileDescriptor, LOCK_UN) }
            guard try file.seekToEnd() == physicalSize else { throw SmalltalkError("The changes log was modified outside this session. Reload the image.") }
            if physicalSize != validSize { try file.truncate(atOffset: validSize) }
            do {
                try file.write(contentsOf: bytes)
                try file.synchronize()
            } catch {
                try? file.truncate(atOffset: validSize)
                throw error
            }
            validSize += UInt64(bytes.count); physicalSize = validSize
        }
        records.append(record)
        memoryBytes += bytes.count
        return record
    }
    static func read(_ url: URL) throws -> SourceJournal {
        let bytes = try readBounded(url, maximum: maxBytes)
        guard let newline = bytes.firstIndex(of: 10) else { throw SmalltalkError("The changes log header is missing or incomplete.") }
        let decoder = JSONDecoder()
        let header = try decoder.decode(Header.self, from: bytes[..<newline])
        guard header.format == "st80-changes", header.version == 1 else { throw SmalltalkError("Unknown changes log format.") }
        var cursor = bytes.index(after: newline), validEnd = cursor
        var records: [ChangeInfo] = [], identifiers: Set<String> = []
        while let end = bytes[cursor...].firstIndex(of: 10) {
            let record = try decoder.decode(ChangeInfo.self, from: bytes[cursor..<end])
            guard record.sequence == Int64(records.count + 1), identifiers.insert(record.id).inserted,
                  record.source.utf8.count <= 262_144, records.count < 100_000 else { throw SmalltalkError("Invalid changes log entry order or size.") }
            records.append(record); cursor = bytes.index(after: end); validEnd = cursor
        }
        let journal = SourceJournal(id: header.id, records: records)
        journal.url = url; journal.physicalSize = UInt64(bytes.count); journal.validSize = UInt64(validEnd)
        return journal
    }
    static func readBounded(_ url: URL, maximum: Int) throws -> Data {
        guard url.isFileURL else { throw SmalltalkError("Expected a local file.") }
        let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
        var data = Data()
        while data.count <= maximum {
            let chunk = try file.read(upToCount: min(65_536, maximum + 1 - data.count)) ?? Data()
            if chunk.isEmpty { return data }
            data.append(chunk)
        }
        throw SmalltalkError("The file exceeds the \(maximum)-byte limit.")
    }

    static func createFile(_ bytes: Data, at url: URL) throws {
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".st80-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try bytes.write(to: temporary, options: .atomic)
        let file = try FileHandle(forWritingTo: temporary)
        defer { try? file.close() }
        try file.synchronize()
        // moveItem refuses an existing destination; neither an unrelated log nor
        // a shared immutable sources archive may be replaced by Save As.
        try FileManager.default.moveItem(at: temporary, to: url)
    }
}

extension SmalltalkSession {
    public func baseVersion(of selector: String, in className: String, side: MethodSide = .instance) -> ChangeInfo? {
        Self.baselineVersion(of: selector, in: className, side: side)
    }

    nonisolated static func baselineVersion(of selector: String, in className: String, side: MethodSide) -> ChangeInfo? {
        guard let library = try? SystemLibrary.shared.get(), let source = library.sources[side][className]?[selector] else { return nil }
        let prefix = side == .classSide ? "class-sources:" : "sources:"
        return ChangeInfo(id: "\(prefix)\(className)>>\(selector)", sequence: 0, timestamp: Date(timeIntervalSince1970: 0), kind: .method, className: className, selector: selector, superclass: nil, fields: nil, source: source, methodSide: side == .classSide ? side : nil)
    }
    public func startChangeLog(at url: URL) async throws {
        try await worker.submitThrowing { try $0.journal.attach(to: url) }
    }
    /// Imports history for review. Importing a log never executes its code.
    public func importChanges(from url: URL) async throws -> EvaluationResult {
        try await worker.submitThrowing { runtime in
            let imported = try SourceJournal.read(url)
            for record in imported.records {
                try runtime.journal.append(kind: record.kind, className: record.className, selector: record.selector, superclass: record.superclass, fields: record.fields, side: record.side, source: record.source)
            }
            return runtime.snapshot(value: "\(imported.records.count) changes imported for review.")
        }
    }
    public func restoreChange(_ id: String) async -> EvaluationResult {
        await worker.submit { runtime in
            runtime.transcript = ""; runtime.steps = 0; runtime.depth = 0
            do { return try runtime.finishEvaluation(value: runtime.restoreVersion(id)) }
            catch { return runtime.finishEvaluation(error: error.localizedDescription) }
        }
    }
}

extension SmalltalkRuntime {
    func sourceVersion(_ id: String) -> ChangeInfo? {
        if let saved = journal.records.first(where: { $0.id == id }) { return saved }
        let side: MethodSide
        let remainder: Substring
        if id.hasPrefix("class-sources:") {
            side = .classSide
            remainder = id.dropFirst("class-sources:".count)
        } else if id.hasPrefix("sources:") {
            side = .instance
            remainder = id.dropFirst("sources:".count)
        } else {
            return nil
        }
        guard let delimiter = remainder.range(of: ">>") else { return nil }
        return SmalltalkSession.baselineVersion(of: String(remainder[delimiter.upperBound...]),
                                                in: String(remainder[..<delimiter.lowerBound]), side: side)
    }

    func restoreVersion(_ id: String) throws -> String {
        guard let record = sourceVersion(id) else {
            let kind = id.hasPrefix("sources:") || id.hasPrefix("class-sources:") ? "baseline" : "source"
            throw SmalltalkError("This \(kind) version does not exist.")
        }
        switch record.kind {
        case .method:
            guard let stClass = classes[record.className] else {
                throw SmalltalkError("Class \(record.className) is missing. Restore its definition first.")
            }
            try compile(record.source, in: stClass, side: record.side)
        case .classDefinition:
            guard let parent = record.superclass.flatMap({ classes[$0] }), let fields = record.fields else {
                throw SmalltalkError("The superclass of the class being restored is missing.")
            }
            if let existing = classes[record.className] {
                try redefineClass(existing, superclass: parent, fields: fields, source: record.source)
            } else {
                _ = try subclass(of: parent, name: record.className, fields: fields.joined(separator: " "))
            }
        }
        return "Restored: \(record.side.displayName(for: record.className))\(record.selector.map { " » \($0)" } ?? "")"
    }
}
