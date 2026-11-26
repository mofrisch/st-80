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
    public internal(set) var classFields: [String]? = nil
    public var side: MethodSide { methodSide ?? .instance }
}

/// Append before installing accepted code. Each complete JSON line is an
/// independently recoverable record; an interrupted final write is ignored.
final class SourceJournal {
    struct Header: Codable { var format = "st80-changes"; var version = 1; let id: String }
    private struct FileStamp: Equatable {
        let device: dev_t
        let inode: ino_t
        let size: off_t
        let modifiedSeconds: Int
        let modifiedNanoseconds: Int
        let changedSeconds: Int
        let changedNanoseconds: Int

        init(_ status: stat) {
            device = status.st_dev; inode = status.st_ino; size = status.st_size
            modifiedSeconds = status.st_mtimespec.tv_sec; modifiedNanoseconds = status.st_mtimespec.tv_nsec
            changedSeconds = status.st_ctimespec.tv_sec; changedNanoseconds = status.st_ctimespec.tv_nsec
        }
    }
    static let maxBytes = 64 * 1024 * 1024
    static let maxRecords = 100_000
    let id: String
    private(set) var records: [ChangeInfo]
    private(set) var url: URL?
    private var physicalSize: UInt64 = 0
    // The complete header and records, excluding any interrupted tail. Zero
    // means the size of an unattached journal has not been calculated yet.
    private var validSize: UInt64 = 0
    private var validatedFileStamp: FileStamp?
    var savedSequence: Int64 = 0
    var sequence: Int64 { records.last?.sequence ?? 0 }

    init(id: String = UUID().uuidString, records: [ChangeInfo] = []) {
        self.id = id; self.records = records
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

    /// Keep cooperating writers out between validating the companion and
    /// committing an image that relies on its current records.
    func withValidatedFile<T>(_ operation: () throws -> T) throws -> T {
        try withValidatedFileHandle { _ in try operation() }
    }

    /// Append and image commits validate the same records while holding the
    /// lock on the exact file descriptor the operation will use.
    private func withValidatedFileHandle<T>(_ operation: (FileHandle) throws -> T) throws -> T {
        guard let url else { throw SmalltalkError("The changes log is not attached to a file.") }
        let file = try FileHandle(forUpdating: url)
        defer { try? file.close() }
        guard flock(file.fileDescriptor, LOCK_EX | LOCK_NB) == 0 else {
            throw SmalltalkError("Another session is writing to the changes log.")
        }
        defer { flock(file.fileDescriptor, LOCK_UN) }
        var opened = stat(), current = stat()
        guard fstat(file.fileDescriptor, &opened) == 0, stat(url.path, &current) == 0,
              opened.st_dev == current.st_dev, opened.st_ino == current.st_ino,
              try file.seekToEnd() == physicalSize else { throw Self.modifiedFile() }
        let stamp = FileStamp(opened)
        // A stable, already validated file needs no repeated whole-log decode.
        // Any inode, size, mtime or ctime change requires a full record check.
        if validatedFileStamp != stamp {
            try file.seek(toOffset: 0)
            let stored = try Self.decode(Self.readBounded(file, maximum: Self.maxBytes), at: url)
            guard stored.id == id, stored.validSize == validSize,
                  try stored.data() == data() else { throw Self.modifiedFile() }
        }
        // An editor may replace a pathname without honoring flock. Detect a
        // replacement or content change that happened while reading the log.
        guard stat(url.path, &current) == 0, stamp == FileStamp(current) else { throw Self.modifiedFile() }
        validatedFileStamp = stamp
        return try operation(file)
    }

    private static func modifiedFile() -> SmalltalkError {
        SmalltalkError("The changes log was modified outside this session. Reload the image.")
    }
    @discardableResult
    func append(kind: ChangeInfo.Kind, className: String, selector: String? = nil, superclass: String? = nil, fields: [String]? = nil,
                classFields: [String] = [], side: MethodSide = .instance, source: String,
                writing: (FileHandle, Data) throws -> Void = { try $0.write(contentsOf: $1) }) throws -> ChangeInfo {
        try checkCapacity(for: 1)
        let record = ChangeInfo(id: UUID().uuidString, sequence: sequence + 1, timestamp: Date(), kind: kind, className: className, selector: selector, superclass: superclass, fields: fields, source: source, methodSide: side == .classSide ? side : nil,
                                classFields: classFields.isEmpty ? nil : classFields)
        try appendPrepared([record], writing: writing)
        return record
    }

    /// Import as new entries, preserving their order and source in one append.
    func appendImportedRecords(_ history: [ChangeInfo],
                               writing: (FileHandle, Data) throws -> Void = { try $0.write(contentsOf: $1) }) throws {
        guard !history.isEmpty else { return }
        try checkCapacity(for: history.count)
        let previousSequence = sequence
        let timestamp = Date()
        let prepared = history.enumerated().map { index, entry in
            ChangeInfo(id: UUID().uuidString, sequence: previousSequence + Int64(index) + 1, timestamp: timestamp,
                       kind: entry.kind, className: entry.className, selector: entry.selector, superclass: entry.superclass,
                       fields: entry.fields, source: entry.source, methodSide: entry.side == .classSide ? .classSide : nil,
                       classFields: entry.classFields)
        }
        try appendPrepared(prepared, writing: writing)
    }

    private func checkCapacity(for count: Int) throws {
        guard count <= Self.maxRecords - records.count else {
            throw SmalltalkError("The changes log contains too many entries.")
        }
    }

    private func appendPrepared(_ prepared: [ChangeInfo], writing: (FileHandle, Data) throws -> Void) throws {
        let currentSize = validSize == 0 ? try data().count : Int(validSize)
        var bytes = Data()
        for record in prepared {
            let line = try Self.line(record)
            guard currentSize + bytes.count + line.count <= Self.maxBytes else {
                throw SmalltalkError("The changes log exceeds the 64 MiB limit.")
            }
            bytes.append(line)
        }
        let newSize = UInt64(currentSize + bytes.count)
        if url != nil {
            try withValidatedFileHandle { file in
                do {
                    if physicalSize != validSize {
                        try file.truncate(atOffset: validSize)
                        physicalSize = validSize
                    }
                    try file.seek(toOffset: validSize)
                    try writing(file, bytes)
                    try file.synchronize()
                    var written = stat(), current = stat()
                    guard let url, fstat(file.fileDescriptor, &written) == 0, stat(url.path, &current) == 0,
                          FileStamp(written) == FileStamp(current),
                          written.st_size == off_t(newSize) else {
                        throw Self.modifiedFile()
                    }
                    validatedFileStamp = FileStamp(written)
                    physicalSize = newSize
                } catch let writeError {
                    validatedFileStamp = nil
                    do {
                        try file.truncate(atOffset: validSize)
                        // A repaired incomplete tail is now gone even when
                        // this append fails. A retry must validate that size.
                        physicalSize = validSize
                        try file.synchronize()
                    } catch {
                        throw SmalltalkError("Could not roll back the changes log after a failed write. Reload the image. Write: \(writeError.localizedDescription) Rollback: \(error.localizedDescription)")
                    }
                    throw writeError
                }
            }
        }
        validSize = newSize
        records.append(contentsOf: prepared)
    }
    static func read(_ url: URL) throws -> SourceJournal {
        let bytes = try readBounded(url, maximum: maxBytes)
        return try decode(bytes, at: url)
    }

    private static func decode(_ bytes: Data, at url: URL) throws -> SourceJournal {
        guard let newline = bytes.firstIndex(of: 10) else { throw SmalltalkError("The changes log header is missing or incomplete.") }
        let decoder = JSONDecoder()
        let header = try decoder.decode(Header.self, from: bytes[..<newline])
        guard header.format == "st80-changes", header.version == 1 else { throw SmalltalkError("Unknown changes log format.") }
        var cursor = bytes.index(after: newline), validEnd = cursor
        var records: [ChangeInfo] = [], identifiers: Set<String> = []
        while let end = bytes[cursor...].firstIndex(of: 10) {
            let record = try decoder.decode(ChangeInfo.self, from: bytes[cursor..<end])
            guard record.sequence == Int64(records.count + 1), identifiers.insert(record.id).inserted,
                  record.source.utf8.count <= 262_144, records.count < maxRecords else { throw SmalltalkError("Invalid changes log entry order or size.") }
            records.append(record); cursor = bytes.index(after: end); validEnd = cursor
        }
        let journal = SourceJournal(id: header.id, records: records)
        journal.url = url; journal.physicalSize = UInt64(bytes.count); journal.validSize = UInt64(validEnd)
        return journal
    }
    static func readBounded(_ url: URL, maximum: Int) throws -> Data {
        guard url.isFileURL else { throw SmalltalkError("Expected a local file.") }
        let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
        return try readBounded(file, maximum: maximum)
    }

    private static func readBounded(_ file: FileHandle, maximum: Int) throws -> Data {
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
    /// Appends the imported history as a batch for review, without executing its code.
    public func importChanges(from url: URL) async throws -> EvaluationResult {
        try await worker.submitThrowing { runtime in
            let imported = try SourceJournal.read(url)
            try runtime.journal.appendImportedRecords(imported.records)
            return runtime.snapshot(value: "\(imported.records.count) changes imported for review.")
        }
    }
    public func restoreChange(_ id: String) async -> EvaluationResult {
        await worker.submit { runtime in
            runtime.beginEvaluation()
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
                try redefineClass(existing, superclass: parent, fields: fields, classFields: record.classFields ?? [], source: record.source)
            } else {
                _ = try subclass(of: parent, name: record.className, fields: fields.joined(separator: " "), classFields: record.classFields ?? [])
            }
        }
        return "Restored: \(record.side.displayName(for: record.className))\(record.selector.map { " » \($0)" } ?? "")"
    }
}
