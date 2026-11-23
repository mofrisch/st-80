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
        guard data.count <= Self.maxBytes else { throw SmalltalkError("Das Changes-Protokoll ist zu groß (64 MiB).") }
        return data
    }
    func attach(to url: URL) throws {
        guard url.isFileURL else { throw SmalltalkError("Changes-Protokolle müssen lokal gespeichert werden.") }
        guard !FileManager.default.fileExists(atPath: url.path) else { throw SmalltalkError("Das Changes-Protokoll \(url.lastPathComponent) existiert bereits. Wähle einen anderen Image-Namen.") }
        let bytes = try data()
        try Self.createFile(bytes, at: url)
        self.url = url; physicalSize = UInt64(bytes.count); validSize = physicalSize
    }
    @discardableResult
    func append(kind: ChangeInfo.Kind, className: String, selector: String? = nil, superclass: String? = nil, fields: [String]? = nil, source: String) throws -> ChangeInfo {
        guard records.count < 100_000 else { throw SmalltalkError("Changes-Protokoll enthält zu viele Einträge.") }
        let record = ChangeInfo(id: UUID().uuidString, sequence: sequence + 1, timestamp: Date(), kind: kind, className: className, selector: selector, superclass: superclass, fields: fields, source: source)
        let bytes = try Self.line(record)
        guard validSize + UInt64(bytes.count) <= Self.maxBytes, memoryBytes + bytes.count <= Self.maxBytes else { throw SmalltalkError("Das Changes-Protokoll ist zu groß (64 MiB).") }
        if let url {
            let file = try FileHandle(forUpdating: url)
            defer { try? file.close() }
            guard flock(file.fileDescriptor, LOCK_EX | LOCK_NB) == 0 else { throw SmalltalkError("Das Changes-Protokoll wird gerade von einer anderen Sitzung geschrieben.") }
            defer { flock(file.fileDescriptor, LOCK_UN) }
            guard try file.seekToEnd() == physicalSize else { throw SmalltalkError("Das Changes-Protokoll wurde außerhalb dieser Sitzung verändert; lade das Image erneut.") }
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
        guard let newline = bytes.firstIndex(of: 10) else { throw SmalltalkError("Changes-Kopf fehlt oder ist unvollständig.") }
        let decoder = JSONDecoder()
        let header = try decoder.decode(Header.self, from: bytes[..<newline])
        guard header.format == "st80-changes", header.version == 1 else { throw SmalltalkError("Unbekanntes Changes-Format.") }
        var cursor = bytes.index(after: newline), validEnd = cursor
        var records: [ChangeInfo] = [], identifiers: Set<String> = []
        while let end = bytes[cursor...].firstIndex(of: 10) {
            let record = try decoder.decode(ChangeInfo.self, from: bytes[cursor..<end])
            guard record.sequence == Int64(records.count + 1), identifiers.insert(record.id).inserted,
                  record.source.utf8.count <= 262_144, records.count < 100_000 else { throw SmalltalkError("Ungültige Changes-Reihenfolge oder Eintragsgröße.") }
            records.append(record); cursor = bytes.index(after: end); validEnd = cursor
        }
        let journal = SourceJournal(id: header.id, records: records)
        journal.url = url; journal.physicalSize = UInt64(bytes.count); journal.validSize = UInt64(validEnd)
        return journal
    }
    static func readBounded(_ url: URL, maximum: Int) throws -> Data {
        guard url.isFileURL else { throw SmalltalkError("Eine lokale Datei wird erwartet.") }
        let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
        var data = Data()
        while data.count <= maximum {
            let chunk = try file.read(upToCount: min(65_536, maximum + 1 - data.count)) ?? Data()
            if chunk.isEmpty { return data }
            data.append(chunk)
        }
        throw SmalltalkError("Datei ist zu groß (maximal \(maximum) Bytes).")
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
    public func baseVersion(of selector: String, in className: String) -> ChangeInfo? {
        guard let library = try? SystemLibrary.shared.get(), let source = library.methods[className]?[selector] else { return nil }
        return ChangeInfo(id: "sources:\(className)>>\(selector)", sequence: 0, timestamp: Date(timeIntervalSince1970: 0), kind: .method, className: className, selector: selector, superclass: nil, fields: nil, source: source)
    }
    public func startChangeLog(at url: URL) async throws {
        try await worker.submitThrowing { try $0.journal.attach(to: url) }
    }
    /// Imports history for review. Importing a log never executes its code.
    public func importChanges(from url: URL) async throws -> EvaluationResult {
        try await worker.submitThrowing { runtime in
            let imported = try SourceJournal.read(url)
            for record in imported.records {
                try runtime.journal.append(kind: record.kind, className: record.className, selector: record.selector, superclass: record.superclass, fields: record.fields, source: record.source)
            }
            return runtime.snapshot(value: "\(imported.records.count) Änderungen zum Prüfen eingelesen.")
        }
    }
    public func restoreChange(_ id: String) async -> EvaluationResult {
        await worker.submit { runtime in
            runtime.transcript = ""; runtime.steps = 0; runtime.depth = 0
            do {
                let record: ChangeInfo
                if let saved = runtime.journal.records.first(where: { $0.id == id }) { record = saved }
                else if id.hasPrefix("sources:") {
                    let parts = String(id.dropFirst(8)).components(separatedBy: ">>")
                    guard parts.count == 2, let source = try SystemLibrary.shared.get().methods[parts[0]]?[parts[1]] else { throw SmalltalkError("Diese Basisversion existiert nicht.") }
                    record = ChangeInfo(id: id, sequence: 0, timestamp: Date(timeIntervalSince1970: 0), kind: .method, className: parts[0], selector: parts[1], superclass: nil, fields: nil, source: source)
                } else { throw SmalltalkError("Diese Quelltextversion existiert nicht.") }
                switch record.kind {
                case .method:
                    guard let stClass = runtime.classes[record.className] else { throw SmalltalkError("Klasse \(record.className) fehlt; stelle zuerst deren Definition wieder her.") }
                    try runtime.compile(record.source, in: stClass)
                case .classDefinition:
                    if let existing = runtime.classes[record.className] {
                        guard existing.superclass?.name == record.superclass, existing.ownFields == record.fields else { throw SmalltalkError("Die Klasse existiert mit einem anderen Layout.") }
                    } else {
                        guard let parent = record.superclass.flatMap({ runtime.classes[$0] }), let fields = record.fields else { throw SmalltalkError("Oberklasse der wiederherzustellenden Klasse fehlt.") }
                        _ = try runtime.subclass(of: parent, name: record.className, fields: fields.joined(separator: " "))
                    }
                }
                return runtime.finishEvaluation(value: "Wiederhergestellt: \(record.className)\(record.selector.map { " » \($0)" } ?? "")")
            } catch { return runtime.finishEvaluation(error: error.localizedDescription) }
        }
    }
}
