import Foundation

public enum InspectionMember: Hashable, Sendable {
    case field(String)
    /// Smalltalk arrays are indexed starting at one.
    case index(Int)

    var name: String {
        switch self {
        case .field(let name): name
        case .index(let index): "[\(index)]"
        }
    }
}

public struct InspectorRow: Identifiable, Sendable {
    public let id: InspectionMember
    public let name: String
    public let className: String
    public let preview: String
}

public struct InspectorSnapshot: Identifiable, Sendable {
    public let id: UUID
    public let className: String
    public let summary: String
    public let rows: [InspectorRow]
    public let path: [String]
    /// Zero-based page of the current object's members.
    public let page: Int
    public let pageCount: Int
    public let itemCount: Int
}

public enum InspectorAction: Sendable {
    case refresh, follow(InspectionMember), back, page(Int)
}

/// Only the interpreter worker holds the values. Native windows use snapshots.
struct ObjectInspectorState {
    fileprivate struct Level {
        let value: Value
        let name: String
        var page = 0
    }

    fileprivate var levels: [Level]
}

extension SmalltalkSession {
    public func inspect(_ id: UUID, action: InspectorAction) async -> InspectorSnapshot? {
        await worker.submit { $0.updateInspection(id, action: action) }
    }

    public func closeInspector(_ id: UUID) async {
        await worker.submit { runtime in
            _ = runtime.objectInspectors.removeValue(forKey: id)
        }
    }
}

extension SmalltalkRuntime {
    private static let inspectorPageSize = 100
    private static let inspectorDepthLimit = 64
    private static let inspectorWindowLimit = 32

    var inspectorRoots: [Value] {
        objectInspectors.values.flatMap { $0.levels.map(\.value) }
    }

    func requestInspection(_ value: Value) throws {
        guard objectInspectors.count < Self.inspectorWindowLimit else {
            throw SmalltalkError("Close an Object Inspector before opening another one.")
        }
        let id = UUID()
        let root = ObjectInspectorState.Level(value: value, name: inspectionClassName(value))
        let state = ObjectInspectorState(levels: [root])
        objectInspectors[id] = state
        toolRequests.append(.openInspector(inspectionSnapshot(id, state: state)))
    }

    fileprivate func updateInspection(_ id: UUID, action: InspectorAction) -> InspectorSnapshot? {
        guard var state = objectInspectors[id], let current = state.levels.last else { return nil }
        switch action {
        case .refresh:
            break
        case .back:
            if state.levels.count > 1 { state.levels.removeLast() }
        case .page(let page):
            state.levels[state.levels.count - 1].page = page
        case .follow(let member):
            if let value = inspectionValue(member, in: current.value) {
                // A cycle leads back to the matching object already in the path.
                if let match = state.levels.lastIndex(where: { sameInspectionReference($0.value, value) }) {
                    state.levels.removeSubrange((match + 1)...)
                } else if state.levels.count < Self.inspectorDepthLimit {
                    let name = Self.previewText(member.name, limit: 160)
                    state.levels.append(.init(value: value, name: name))
                }
            }
        }
        let snapshot = inspectionSnapshot(id, state: state)
        state.levels[state.levels.count - 1].page = snapshot.page
        objectInspectors[id] = state
        return snapshot
    }

    private func inspectionSnapshot(_ id: UUID, state: ObjectInspectorState) -> InspectorSnapshot {
        // Every inspection has a root, and navigation never removes it.
        let level = state.levels[state.levels.count - 1]
        let fields = inspectionFields(level.value)
        let array: STArray?
        if case .array(let value) = level.value { array = value } else { array = nil }
        let itemCount = array?.elements.count ?? fields.count
        let pageCount = max(1, (itemCount + Self.inspectorPageSize - 1) / Self.inspectorPageSize)
        let page = min(max(0, level.page), pageCount - 1)
        let start = page * Self.inspectorPageSize
        let end = min(start + Self.inspectorPageSize, itemCount)
        let rows = (start..<end).map { offset in
            let member: InspectionMember
            let value: Value
            if let array {
                member = .index(offset + 1)
                value = array.elements[offset]
            } else {
                member = .field(fields[offset].name)
                value = fields[offset].value
            }
            return InspectorRow(id: member, name: Self.previewText(member.name, limit: 160),
                                className: inspectionClassName(value), preview: inspectionPreview(value, limit: 96))
        }
        return InspectorSnapshot(id: id, className: inspectionClassName(level.value),
                                 summary: inspectionPreview(level.value, limit: 4096, multiline: true),
                                 rows: rows, path: state.levels.map(\.name), page: page, pageCount: pageCount,
                                 itemCount: itemCount)
    }

    private func inspectionFields(_ value: Value) -> [(name: String, value: Value)] {
        switch value {
        case .object(let object):
            return object.stClass.fields.map { ($0, object.fields[$0] ?? .nilValue) }
        case .classObject(let target):
            return [("superclass", target.superclass.map(Value.classObject) ?? .nilValue)]
        case .block(let block):
            return [("receiver", block.context.receiver)]
        default:
            return []
        }
    }

    private func inspectionValue(_ member: InspectionMember, in value: Value) -> Value? {
        switch member {
        case .index(let index):
            guard case .array(let array) = value, index > 0, index <= array.elements.count else { return nil }
            return array.elements[index - 1]
        case .field(let name):
            return inspectionFields(value).first { $0.name == name }?.value
        }
    }

    private func sameInspectionReference(_ a: Value, _ b: Value) -> Bool {
        if case .classObject(let left) = a, case .classObject(let right) = b { return left === right }
        guard let left = HeapReference(a), let right = HeapReference(b) else { return false }
        return left.identity == right.identity
    }

    func inspectionClassName(_ value: Value) -> String {
        Self.previewText(classOf(value).name, limit: 160)
    }

    func inspectionPreview(_ value: Value, limit: Int, multiline: Bool = false) -> String {
        let text: String
        switch value {
        case .object:
            text = "a \(inspectionClassName(value))"
        case .array(let array):
            text = "Array (\(array.elements.count) \(array.elements.count == 1 ? "element" : "elements"))"
        case .block(let block):
            text = "[Block · \(block.parameters.count) \(block.parameters.count == 1 ? "argument" : "arguments")]"
        case .classObject(let target):
            text = "\(Self.previewText(target.name, limit: limit)) class"
        case .string(let string):
            let sample = Self.previewText(string, limit: limit).replacingOccurrences(of: "'", with: "''")
            text = "'\(sample)'"
        case .symbol(let name):
            text = "#\(Self.previewText(name, limit: limit))"
        default:
            text = printValue(value)
        }
        if multiline { return text }
        return text.replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t")
    }

    private static func previewText(_ text: String, limit: Int) -> String {
        let scalars = text.unicodeScalars
        let end = scalars.index(scalars.startIndex, offsetBy: limit, limitedBy: scalars.endIndex) ?? scalars.endIndex
        return end == scalars.endIndex ? text : String(scalars[..<end]) + "…"
    }
}
