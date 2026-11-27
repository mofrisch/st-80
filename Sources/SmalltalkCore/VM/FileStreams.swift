import Darwin
import Foundation

private enum FileStreamFailure: LocalizedError {
    case invalid(String)
    case system(operation: String, code: Int32)

    var errorDescription: String? {
        switch self {
        case .invalid(let message): return message
        case .system(let operation, let code): return "Could not \(operation) file: \(String(cString: strerror(code)))."
        }
    }
}

private func decodeFileText(_ bytes: some Collection<UInt8>) throws -> String {
    // Keep a leading U+FEFF in the stream. A byte round trip rejects any UTF-8
    // repaired by String(decoding:as:), including a truncated final scalar.
    let text = String(decoding: bytes, as: UTF8.self)
    guard text.utf8.elementsEqual(bytes) else { throw FileStreamFailure.invalid("The file contains invalid UTF-8.") }
    return text
}

/// A seekable external backing store. The VM's file cursor counts sequence values;
/// the native offset counts bytes. Neither the descriptor nor the cache is saved.
final class FileStreamHandle {
    enum ExternalType: String { case text, binary }
    enum Mode: String {
        case read, create, append, truncate

        func flags(check: Bool, writableOnly: Bool = false) -> Int32 {
            let access = writableOnly ? O_WRONLY : O_RDWR
            switch self {
            case .read: return O_RDONLY
            case .create: return access | O_CREAT | (check ? O_EXCL : 0)
            case .append, .truncate: return access | (check ? 0 : O_CREAT)
            }
        }
    }

    struct Cursor {
        var offset: Int64 = 0
        var position: Int64 = 0
    }

    let type: ExternalType
    let mode: Mode
    private let file: FileHandle
    private let writableOnly: Bool
    private let hasUnreadableTextPrefix: Bool
    private var shadow: FileHandle?
    private static let chunkSize = 4_096
    private var cache = Data()
    private var cacheOffset: Int64 = 0
    var cursor = Cursor()

    init(path: String, mode: Mode, check: Bool, type: ExternalType) throws {
        let flags = O_CLOEXEC | O_NONBLOCK
        let permissions = mode_t(0o666)
        var descriptor = open(path, mode.flags(check: check) | flags, permissions)
        let writableOnly = descriptor < 0 && mode != .read && (errno == EACCES || errno == EPERM)
        if writableOnly {
            descriptor = open(path, mode.flags(check: check, writableOnly: true) | flags, permissions)
        }
        guard descriptor >= 0 else { throw FileStreamFailure.system(operation: "open", code: errno) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var info = stat()
        guard fstat(descriptor, &info) == 0 else {
            throw FileStreamFailure.system(operation: "inspect", code: errno)
        }
        guard (info.st_mode & S_IFMT) == S_IFREG else {
            throw FileStreamFailure.invalid("FileStream expects a regular file.")
        }
        let startsEmpty = mode == .create || mode == .truncate || info.st_size == 0
        // Preserve readable stream contents for bytes written from an empty
        // backing store without broadening the external file's permissions.
        self.shadow = writableOnly && startsEmpty ? try Self.openShadow() : nil
        if mode == .create || mode == .truncate {
            try handle.truncate(atOffset: 0)
        }
        file = handle
        self.writableOnly = writableOnly
        hasUnreadableTextPrefix = writableOnly && !startsEmpty && type == .text
        self.type = type
        self.mode = mode
    }

    private static func openShadow() throws -> FileHandle {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("st80-file-stream.XXXXXX")
        var template = temporary.path.utf8CString
        return try template.withUnsafeMutableBufferPointer { buffer in
            let path = buffer.baseAddress!
            let descriptor = mkstemp(path)
            guard descriptor >= 0 else { throw FileStreamFailure.system(operation: "create stream backing", code: errno) }
            let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            guard unlink(path) == 0 else { throw FileStreamFailure.system(operation: "unlink stream backing", code: errno) }
            return handle
        }
    }

    func close() throws {
        if mode != .read { try flush() }
        try file.close()
    }

    func flush() throws { try file.synchronize() }

    func byteCount() throws -> Int64 {
        var info = stat()
        guard fstat(file.fileDescriptor, &info) == 0 else {
            throw FileStreamFailure.system(operation: "inspect", code: errno)
        }
        return info.st_size
    }

    func bytes(at offset: Int64, count: Int) throws -> Data {
        if count == 0 { return Data() }
        guard let input = writableOnly ? shadow : file else {
            throw FileStreamFailure.system(operation: "read", code: EACCES)
        }
        try input.seek(toOffset: UInt64(offset))
        return try input.read(upToCount: count) ?? Data()
    }

    private func byte(at offset: Int64, charge: (Int) throws -> Void) throws -> UInt8? {
        let index = offset - cacheOffset
        if index >= 0 && index < cache.count { return cache[Int(index)] }
        try charge(0)
        let chunk = try bytes(at: offset, count: Self.chunkSize)
        try charge(chunk.count)
        cache = chunk
        cacheOffset = offset
        return cache.first
    }

    func next(at cursor: inout Cursor, charge: (Int) throws -> Void) throws -> Value? {
        guard let first = try byte(at: cursor.offset, charge: charge) else { return nil }
        var width = 1
        let value: Value
        if type == .binary {
            value = .integer(Int64(first))
        } else if first < 0x80 {
            value = .character(UInt32(first))
        } else {
            switch first {
            case 0xc2...0xdf: width = 2
            case 0xe0...0xef: width = 3
            case 0xf0...0xf4: width = 4
            default: throw Self.invalidUTF8
            }
            var encoded = [first]
            for index in 1..<width {
                guard let byte = try byte(at: cursor.offset + Int64(index), charge: charge) else {
                    throw Self.invalidUTF8
                }
                encoded.append(byte)
            }
            guard let scalar = try decodeFileText(encoded).unicodeScalars.first else {
                throw Self.invalidUTF8
            }
            value = .character(scalar.value)
        }
        cursor.offset += Int64(width)
        cursor.position += 1
        return value
    }

    private static var invalidUTF8: FileStreamFailure { .invalid("The file contains invalid UTF-8.") }

    func advanced(from start: Cursor, by count: Int64, charge: (Int) throws -> Void) throws -> Cursor {
        if type == .binary {
            let available = max(0, try byteCount() - start.offset)
            let end = start.offset + min(available, count)
            return Cursor(offset: end, position: end)
        }
        var end = start
        while end.position - start.position < count {
            guard try next(at: &end, charge: charge) != nil else { break }
        }
        return end
    }

    func seek(to position: Int64?, charge: (Int) throws -> Void) throws {
        if position == 0 {
            cache.removeAll()
            cursor = Cursor()
            return
        }
        if hasUnreadableTextPrefix {
            // End-of-file is usable for appending even when the number of
            // Unicode scalars in the existing bytes cannot be determined.
            guard position == nil else { throw FileStreamFailure.system(operation: "read", code: EACCES) }
            cursor = Cursor(offset: try byteCount())
            return
        }
        let start = position.map { $0 < cursor.position } == true ? Cursor() : cursor
        let end = try advanced(from: start, by: position.map { $0 - start.position } ?? Int64.max, charge: charge)
        if let position {
            guard end.position == position, end.offset < (try byteCount()) else {
                throw FileStreamFailure.invalid("Position outside the file stream.")
            }
        }
        cursor = end
    }

    func sequencePosition() throws -> Int64 {
        guard !hasUnreadableTextPrefix || cursor.offset == 0 else {
            throw FileStreamFailure.invalid("Cannot determine the text position without read access to the file.")
        }
        return cursor.position
    }

    func write(_ data: Data, elementCount: Int, charge: (Int) throws -> Void) throws {
        guard !data.isEmpty else { return }
        let endOfFile = try byteCount()
        let endOfReplacement = cursor.offset == endOfFile ? endOfFile
            : try advanced(from: cursor, by: Int64(elementCount), charge: charge).offset
        guard endOfReplacement <= endOfFile else {
            throw FileStreamFailure.invalid("The file shrank before the write.")
        }
        guard Int64(data.count) <= Int64.max - cursor.offset else {
            throw FileStreamFailure.invalid("The file would be too large.")
        }
        let newEnd = cursor.offset + Int64(data.count)
        let shift = newEnd - endOfReplacement
        let tailSize = endOfFile - endOfReplacement
        guard shift <= Int64.max - endOfFile else {
            throw FileStreamFailure.invalid("The file would be too large.")
        }
        // Charge before moving bytes so cancellation cannot leave a half-shifted suffix.
        if shift != 0 && tailSize > 0 {
            try charge(Int(tailSize))
        }
        cache.removeAll()
        var committed = false
        defer {
            if !committed { shadow = nil }
        }
        if shift > 0 && tailSize > 0 {
            var stop = endOfFile
            while stop > endOfReplacement {
                let start = max(endOfReplacement, stop - Int64(Self.chunkSize))
                try moveBytes(from: start, to: start + shift, count: Int(stop - start))
                stop = start
            }
        } else if shift < 0 {
            var start = endOfReplacement
            while start < endOfFile {
                let count = Int(min(endOfFile - start, Int64(Self.chunkSize)))
                try moveBytes(from: start, to: start + shift, count: count)
                start += Int64(count)
            }
            let truncatedSize = UInt64(endOfFile + shift)
            try file.truncate(atOffset: truncatedSize)
            try shadow?.truncate(atOffset: truncatedSize)
        }
        try store(data, at: cursor.offset)
        cursor = Cursor(offset: newEnd, position: cursor.position + Int64(elementCount))
        committed = true
    }

    private func moveBytes(from source: Int64, to target: Int64, count: Int) throws {
        let chunk = try bytes(at: source, count: count)
        guard chunk.count == count else { throw FileStreamFailure.invalid("The file shrank during the write.") }
        try store(chunk, at: target)
    }

    private func store(_ data: Data, at offset: Int64) throws {
        try file.seek(toOffset: UInt64(offset))
        try file.write(contentsOf: data)
        if let shadow {
            try shadow.seek(toOffset: UInt64(offset))
            try shadow.write(contentsOf: data)
        }
    }
}

extension SmalltalkRuntime {
    /// The shipped stream and enumeration methods are pure with these backing
    /// types. Keep large transfers within the execution budget, while allowing
    /// current-image method edits and user collections to use ordinary sends.
    func nextPutAllBatch(_ stream: STObject, source: Value) throws -> Value? {
        let name = stream.stClass.name
        let receiver = Value.object(stream)
        let isFileStream = name == "WriteFileStream"
        guard isFileStream || name == "WriteStream" || name == "ReadWriteStream" else { return nil }
        guard let library = try? SystemLibrary.shared.get(), let arrayClass = classes["Array"] else { return .nilValue }

        func isShipped(_ selector: String, on object: Value, owner name: String, side: MethodSide = .instance) -> Bool {
            guard let (method, owner, methodSide) = lookupMethod(selector, on: object),
                  owner.name == name, methodSide == side else { return false }
            return library.sources[side][name]?[selector] == method.source
        }

        guard isShipped("nextPut:", on: receiver, owner: name),
              isShipped("with:", on: .classObject(arrayClass), owner: "Array", side: .classSide) else {
            return .nilValue
        }
        if isFileStream {
            guard lookupMethod("_writeFileElements:", on: receiver) == nil else { return .nilValue }
        } else {
            guard let backing = stream.fields["backing"],
                  lookupMethod("_commitWrite:", on: receiver) == nil,
                  ["Array", "OrderedCollection", "String", "ByteArray"].contains(classOf(backing).name),
                  ["_write:", "_sequence", "_checkWrite:"].allSatisfy({
                      isShipped($0, on: receiver, owner: "CollectionStream")
                  }) else { return .nilValue }
        }

        if classOf(source).name == "ByteArray" {
            guard case .object(let bytes) = source, let storage = bytes.fields["storage"], case .array(let array) = storage,
                  isShipped("do:", on: source, owner: "ByteArray"), lookupMethod("do:", on: storage) == nil,
                  classes["BlockClosure"]?.lookup("value:") == nil,
                  lookupMethod("ifNil:", on: .nilValue) == nil, lookupMethod("ifNil:", on: .integer(0)) == nil else {
                return .nilValue
            }
            if isFileStream { return source }
            try chargeNumericWork(array.elements.count)
            return try self.array(array.elements.map { isNil($0) ? .integer(0) : $0 })
        }

        guard lookupMethod("do:", on: source) == nil else { return .nilValue }
        if case .array = source { return source }
        guard source.textContents != nil else { return .nilValue }
        return isFileStream ? source : try array(sequenceElements(source))
    }

    func fileStreamPrimitive(_ stream: STObject, _ selector: String, _ args: [Value]) throws -> Value {
        do {
            return try performFileStreamPrimitive(stream, selector, args)
        } catch let error where error is FileStreamFailure || error is CocoaError || error is POSIXError {
            return try send(.object(stream), "error:", [.string(error.localizedDescription)])
        }
    }

    private func performFileStreamPrimitive(_ stream: STObject, _ selector: String, _ args: [Value]) throws -> Value {
        if selector == "_openFile:mode:check:type:" {
            let path: String?
            if case .symbol(let name) = args[0] {
                path = name
            } else {
                path = args[0].textContents
            }
            guard stream.fileStream == nil, let path, !path.isEmpty, !path.utf8.contains(0),
                  case .symbol(let modeName) = args[1], let mode = FileStreamHandle.Mode(rawValue: modeName),
                  case .boolean(let check) = args[2],
                  case .symbol(let typeName) = args[3], let type = FileStreamHandle.ExternalType(rawValue: typeName),
                  let streamClass = classes[mode == .read ? "ReadFileStream" : "WriteFileStream"],
                  stream.stClass.inherits(from: streamClass) else {
                throw FileStreamFailure.invalid("Invalid file path, mode, check flag or external type.")
            }
            let file = try FileStreamHandle(path: path, mode: mode, check: check, type: type)
            if mode == .append { try file.seek(to: nil, charge: chargeNumericWork) }
            stream.fileStream = file
            stream.fields["externalType"] = .symbol(typeName)
            return .object(stream)
        }

        if selector == "_closeFile" {
            defer { stream.fileStream = nil }
            try stream.fileStream?.close()
            return .object(stream)
        }
        guard let file = stream.fileStream else { throw FileStreamFailure.invalid("The file stream is closed.") }
        switch selector {
        case "_fileContents":
            return try fileCollection(file, from: 0, to: file.byteCount())
        case "_fileIsEmpty":
            return .boolean(try file.byteCount() == 0)
        case "_filePosition":
            return .integer(try file.sequencePosition())
        case "_seekFile:":
            try file.seek(to: fileCount(args[0]), charge: chargeNumericWork)
        case "_seekFileToEnd":
            try file.seek(to: nil, charge: chargeNumericWork)
        case "_fileAtEnd":
            return .boolean(try file.cursor.offset >= file.byteCount())
        case "_peekFileElement", "_readFileElement":
            var end = file.cursor
            let value = try file.next(at: &end, charge: chargeNumericWork)
            if selector == "_readFileElement" { file.cursor = end }
            return value ?? .nilValue
        case "_skipFileElements:":
            file.cursor = try file.advanced(from: file.cursor, by: fileCount(args[0], overflow: Int64.max),
                                            charge: chargeNumericWork)
        case "_readFileElements:":
            let start = file.cursor.offset
            let limit = fileCollectionLimit(file)
            let count = try fileCount(args[0], overflow: Int64.max)
            let end = try file.advanced(from: file.cursor, by: min(count, Int64(limit + 1)), charge: chargeNumericWork)
            let result = try fileCollection(file, from: start, to: end.offset)
            file.cursor = end
            return result
        case "_scanFileUntil:collecting:":
            guard case .array(let candidates) = args[0], candidates.elements.count <= 2,
                  case .boolean(let collect) = args[1] else {
                throw FileStreamFailure.invalid("Invalid file stream search.")
            }
            return try scanFile(file, until: candidates.elements, collecting: collect)
        case "_writeFileElements:":
            let (data, count) = try fileData(args[0], type: file.type)
            guard stream.fileStream === file else {
                throw FileStreamFailure.invalid("The file stream was closed while preparing the write.")
            }
            try file.write(data, elementCount: count, charge: chargeNumericWork)
        case "_flushFile":
            try file.flush()
        default:
            preconditionFailure("Unknown file stream primitive: \(selector)")
        }
        return .object(stream)
    }

    private func fileCount(_ value: Value, overflow: Int64? = nil) throws -> Int64 {
        if case .integer(let count) = value, count >= 0 { return count }
        if case .largeInteger(let count) = value, count >= .zero, let overflow { return overflow }
        throw FileStreamFailure.invalid("Expected a nonnegative integer within range.")
    }

    private func scanFile(_ file: FileStreamHandle, until candidates: [Value], collecting: Bool) throws -> Value {
        let start = file.cursor.offset
        var end = file.cursor
        var stop = end.offset
        var match = Value.nilValue
        let limit = Int64(fileCollectionLimit(file))
        while let element = try file.next(at: &end, charge: chargeNumericWork) {
            if try candidates.contains(where: { try equal(element, $0) }) {
                match = element
                break
            }
            stop = end.offset
            if collecting && stop - start > limit {
                throw FileStreamFailure.invalid("The result exceeds the file stream's collection size limit.")
            }
        }
        let contents = collecting ? try fileCollection(file, from: start, to: stop) : .nilValue
        let result = try array([contents, match])
        file.cursor = end
        return result
    }

    private func fileCollectionLimit(_ file: FileStreamHandle) -> Int {
        file.type == .binary ? arrayLimit : (compilationMode ? 262_144 : 65_536)
    }

    private func fileCollection(_ file: FileStreamHandle, from start: Int64, to end: Int64) throws -> Value {
        let size = end - start
        guard size <= fileCollectionLimit(file) else {
            throw FileStreamFailure.invalid("The result exceeds the file stream's collection size limit.")
        }
        try chargeNumericWork(Int(size))
        let data = try file.bytes(at: start, count: Int(size))
        guard data.count == size else { throw FileStreamFailure.invalid("The file shrank during the read.") }
        if file.type == .text {
            return try newString(decodeFileText(data))
        }
        guard let byteArray = classes["ByteArray"], byteArray.fields.contains("storage") else {
            throw FileStreamFailure.invalid("The ByteArray class is unavailable.")
        }
        let storage = try array(data.map { .integer(Int64($0)) })
        return try withRoots([storage]) { _ in
            let collection = try object(byteArray)
            collection.fields["storage"] = storage
            return .object(collection)
        }
    }

    private func fileData(_ collection: Value, type: FileStreamHandle.ExternalType) throws -> (Data, Int) {
        if type == .text, let string = collection.textContents {
            try chargeNumericWork(string.utf8.count)
            return (Data(string.utf8), string.unicodeScalars.count)
        }
        let source: Value
        let nilSlotsAreZero: Bool
        if case .array = collection {
            source = collection
            nilSlotsAreZero = false
        } else if type == .binary, case .object(let bytes) = collection, bytes.stClass === classes["ByteArray"],
                  let storage = bytes.fields["storage"] {
            // Uninitialized indexed slots in ByteArray represent zero.
            source = storage
            nilSlotsAreZero = true
        } else {
            source = try send(collection, "asArray", [])
            nilSlotsAreZero = false
        }
        guard case .array(let array) = source else {
            throw FileStreamFailure.invalid("Expected a collection of file elements.")
        }
        let elements = array.elements
        try chargeNumericWork(elements.count)
        switch type {
        case .binary:
            let data = try Data(elements.map { element in
                if nilSlotsAreZero, case .nilValue = element { return 0 }
                guard case .integer(let value) = element, let byte = UInt8(exactly: value) else {
                    throw FileStreamFailure.invalid("A binary file stream expects integers from 0 to 255.")
                }
                return byte
            })
            return (data, elements.count)
        case .text:
            var text = String()
            for element in elements {
                guard case .character(let point) = element, let scalar = Unicode.Scalar(point) else {
                    throw FileStreamFailure.invalid("A text file stream expects characters.")
                }
                text.unicodeScalars.append(scalar)
            }
            return (Data(text.utf8), elements.count)
        }
    }
}
