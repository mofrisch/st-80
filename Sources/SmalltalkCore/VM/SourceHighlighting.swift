import Foundation

public struct SourceHighlight: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case comment, literal, language
    }

    public let kind: Kind
    /// Half-open UTF-16 range for native attributed text.
    public let range: Range<Int>
}

extension SmalltalkSession {
    private static let sourceScannerWorker = InterpreterWorker(bootstrap: false)

    public func sourceHighlights(_ source: String) async -> [SourceHighlight] {
        guard !source.isEmpty, source.utf8.count <= 65_536, !Task.isCancelled else { return [] }
        let definitions = await worker.submit { runtime in
            SourceScannerDefinition.capture(in: runtime)
        }
        guard let definitions, !Task.isCancelled else { return [] }

        // The interpreter thread supplies only immutable method tables.
        // Scanning does not hold up evaluation or change the live image.
        let cancellation = SourceScanCancellation()
        return await withTaskCancellationHandler {
            await Self.sourceScannerWorker.submit { _ in
                (try? SourceScannerDefinition.scan(source, with: definitions, cancellation: cancellation)) ?? []
            }
        } onCancel: {
            cancellation.cancel()
        }
    }
}

private final class SourceScanCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool { lock.withLock { cancelled } }

    func cancel() { lock.withLock { cancelled = true } }
}

private struct SourceScannerDefinition: Sendable {
    let name: String
    let superclass: String
    let ownFields: [String]
    let methods: SelectorMap<Method>
    let classMethods: SelectorMap<Method>

    static func capture(in runtime: SmalltalkRuntime) -> [Self]? {
        let hierarchy = [("STCompilerList", "Object"), ("STScanner", "Object"), ("STSourceScanner", "STScanner")]
        return try? hierarchy.map { name, parent in
            guard let original = runtime.classes[name], original.superclass === runtime.classes[parent] else {
                throw invalid()
            }
            return Self(name: name, superclass: parent, ownFields: original.ownFields,
                        methods: original.methods, classMethods: original.classMethods)
        }
    }

    static func scan(_ source: String, with definitions: [Self],
                     cancellation: SourceScanCancellation) throws -> [SourceHighlight] {
        guard !cancellation.isCancelled else { return [] }
        let runtime = SmalltalkRuntime(bootstrap: false, compilationMode: true)
        for definition in definitions {
            guard let parent = runtime.classes[definition.superclass] else { throw invalid() }
            let copy = STClass(definition.name, superclass: parent, fields: definition.ownFields)
            copy.methods = definition.methods
            copy.classMethods = definition.classMethods
            runtime.classes[definition.name] = copy
            runtime.globals[definition.name] = .classObject(copy)
        }
        guard let scannerClass = runtime.globals["STSourceScanner"] else { throw invalid() }

        var offsets = [0]
        for character in source {
            offsets.append(offsets[offsets.count - 1] + character.utf16.count)
        }
        let scanner = try runtime.send(scannerClass, "new", [])
        return try runtime.withRoots([scanner]) { _ in
            _ = try runtime.send(scanner, "source:", [.string(source)])
            var highlights: [SourceHighlight] = []
            var previousEnd: Int64 = 1
            while !cancellation.isCancelled {
                let result = try runtime.send(scanner, "nextHighlight", [])
                if case .nilValue = result { return highlights }
                guard case .array(let span) = result, span.elements.count == 3,
                      case .symbol(let name) = span.elements[0], let kind = SourceHighlight.Kind(rawValue: name),
                      case .integer(let start) = span.elements[1], case .integer(let end) = span.elements[2],
                      start >= previousEnd, end > start, end <= offsets.count else { throw invalid() }
                highlights.append(SourceHighlight(kind: kind, range: offsets[Int(start) - 1]..<offsets[Int(end) - 1]))
                previousEnd = end
            }
            return []
        }
    }

    private static func invalid() -> SmalltalkError { SmalltalkError("Invalid Smalltalk source scanner output.") }
}
