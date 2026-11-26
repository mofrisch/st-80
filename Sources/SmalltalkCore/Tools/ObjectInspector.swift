import Foundation

public enum InspectionMember: Hashable, Sendable {
    case field(String)
    /// Smalltalk arrays are indexed starting at one.
    case index(Int)

    fileprivate init?(key: Value) {
        if let name = key.textContents { self = .field(name) }
        else if case .integer(let index) = key, index > 0 { self = .index(Int(index)) }
        else { return nil }
    }

    fileprivate var key: Value {
        switch self {
        case .field(let name): .string(name)
        case .index(let index): .integer(Int64(index))
        }
    }

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
    case refresh, follow(InspectionMember), back, page(Int), previousPage, nextPage
}

extension SmalltalkSession {
    public func inspect(_ id: UUID, action: InspectorAction) async -> InspectorSnapshot? {
        await worker.submit { $0.updateInspection(id, action: action) }
    }

    private static let bundledInspectorWorker = InterpreterWorker()

    package func inspectorWindowInfo(for id: UUID) async throws -> TransientWindowInfo {
        let info: TransientWindowInfo? = try await worker.submitThrowing { runtime in
            guard runtime.objectInspectors[id] != nil else { throw SmalltalkError("Inspection ended.") }
            guard let windowClass = runtime.classes["ObjectInspectorWindow"] else { return nil }
            return try? runtime.inspectorWindowInfo(windowClass)
        }
        if let info { return info }
        return try await Self.bundledInspectorWorker.submitThrowing { runtime in
            try runtime.inspectorWindowInfo(runtime.inspectorWindowClass())
        }
    }

    public func inspectorContent(for snapshot: InspectorSnapshot) async throws -> UIElementInfo {
        let content: UIElementInfo? = try await worker.submitThrowing { runtime in
            guard runtime.objectInspectors[snapshot.id] != nil else { throw SmalltalkError("Inspection ended.") }
            guard runtime.classes["InspectorPresentation"] != nil else { return nil }
            return try runtime.inspectorContent(for: snapshot)
        }
        if let content { return content }
        // Images saved before the presentation class was added still have a
        // working inspector. Render their immutable data with the bundled class.
        return try await Self.bundledInspectorWorker.submitThrowing { runtime in
            try runtime.inspectorContent(for: snapshot)
        }
    }

    package func inspectorAction(_ command: String, row: String?, in snapshot: InspectorSnapshot) async throws -> InspectorSnapshot? {
        try await worker.submitThrowing { runtime in
            try runtime.performInspectorAction(command, row: row, in: snapshot)
        }
    }

    package func inspectorRecoveryContent(_ message: String) async throws -> UIElementInfo {
        try await Self.bundledInspectorWorker.submitThrowing { runtime in
            runtime.steps = 0
            let windowClass = try runtime.inspectorWindowClass()
            let label = String(decoding: message.utf8.prefix(65_533), as: UTF8.self)
            let tree = try runtime.send(.classObject(windowClass), "fallbackFor:", [.string(label)])
            guard let content = try runtime.projectContent(tree) else {
                throw SmalltalkError("The inspector recovery view is missing.")
            }
            return content
        }
    }

    public func closeInspector(_ id: UUID) async {
        await worker.submit { runtime in
            _ = runtime.objectInspectors.removeValue(forKey: id)
        }
    }
}

extension SmalltalkRuntime {
    private static let inspectorWindowLimit = 32

    fileprivate func inspectorWindowClass() throws -> STClass {
        if let windowClass = classes["ObjectInspectorWindow"] { return windowClass }
        return try SystemLibrary.shared.get().bundledClass("ObjectInspectorWindow", in: self)
    }

    fileprivate func inspectorWindowInfo(_ windowClass: STClass) throws -> TransientWindowInfo {
        steps = 0
        return try projectTransientWindow(send(.classObject(windowClass), "new", []))
    }

    fileprivate func performInspectorAction(_ command: String, row: String?, in snapshot: InspectorSnapshot) throws -> InspectorSnapshot? {
        guard let model = objectInspectors[snapshot.id] else { throw SmalltalkError("Inspection ended.") }
        let windowClass = try inspectorWindowClass()
        steps = 0
        let members = try array(snapshot.rows.map(\.id.key))
        let data = try send(.classObject(windowClass), "action:row:on:members:", [
            .symbol(command), row.map(Value.string) ?? .nilValue, model, members,
        ])
        if case .nilValue = data { return nil }
        return try inspectionSnapshot(snapshot.id, from: data)
    }

    fileprivate func inspectorContent(for snapshot: InspectorSnapshot) throws -> UIElementInfo {
        guard let presentation = classes["InspectorPresentation"] else {
            throw SmalltalkError("The inspector presentation class is missing.")
        }
        steps = 0
        return try withRoots { roots in
            let path = try array(snapshot.path.map(Value.string))
            roots.add(path)
            var entries: [Value] = []
            for (index, row) in snapshot.rows.enumerated() {
                let entry = try array([.string(String(index)), .string(row.name), .string(row.preview), .string(row.className)])
                roots.add(entry)
                entries.append(entry)
            }
            let rows = try array(entries)
            roots.add(rows)
            let tree = try send(.classObject(presentation), "contentFor:summary:path:rows:page:pageCount:", [
                .string(snapshot.className), .string(snapshot.summary), path, rows,
                .integer(Int64(snapshot.page)), .integer(Int64(snapshot.pageCount)),
            ])
            guard let content = try projectContent(tree) else {
                throw SmalltalkError("The inspector presentation must provide a control tree.")
            }
            return content
        }
    }

    var inspectorRoots: [Value] { Array(objectInspectors.values) }

    func requestInspection(_ value: Value) throws {
        guard objectInspectors.count < Self.inspectorWindowLimit else {
            throw SmalltalkError("Close an Object Inspector before opening another one.")
        }
        let id = UUID()
        let enclosingDebugger = debugger
        debugger = nil
        // Creating an inspector is part of the current evaluation. Suppress
        // debugger presentation frames without refilling its execution budget.
        defer { debugger = enclosingDebugger }
        try withRoots([value]) { roots in
            let model = try send(.classObject(inspectorModelClass()), "new", [])
            roots.add(model)
            let data = try send(model, "openOn:", [value])
            let snapshot = try inspectionSnapshot(id, from: data)
            objectInspectors[id] = model
            toolRequests.append(.openInspector(snapshot))
        }
    }

    fileprivate func updateInspection(_ id: UUID, action: InspectorAction) -> InspectorSnapshot? {
        guard let model = objectInspectors[id] else { return nil }
        let (selector, arguments): (String, [Value]) = switch action {
        case .refresh: ("refresh", [])
        case .back: ("back", [])
        case .page(let page): ("page:", [.integer(Int64(page))])
        case .previousPage: ("changePageBy:", [.integer(-1)])
        case .nextPage: ("changePageBy:", [.integer(1)])
        case .follow(let member): ("follow:", [member.key])
        }
        steps = 0
        return try? inspectionSnapshot(id, from: send(model, selector, arguments))
    }

    private func inspectorModelClass() throws -> STClass {
        if let model = classes["InspectorModel"] { return model }

        // Older images can use the bundled model without adding it to their
        // class catalog. Its instances are reachable only through the inspector.
        return try SystemLibrary.shared.get().bundledClass("InspectorModel", in: self)
    }

    private func inspectionSnapshot(_ id: UUID, from value: Value) throws -> InspectorSnapshot {
        guard case .array(let data) = value, data.elements.count == 7,
              case .array(let rows) = data.elements[2], case .array(let path) = data.elements[3], !path.elements.isEmpty,
              case .integer(let page) = data.elements[4], case .integer(let pageCount) = data.elements[5],
              case .integer(let itemCount) = data.elements[6], page >= 0, page < pageCount,
              itemCount >= rows.elements.count else { throw invalidInspectionSnapshot() }
        return try InspectorSnapshot(id: id, className: string(data.elements[0]), summary: string(data.elements[1]),
                                     rows: rows.elements.map { value in
            guard case .array(let row) = value, row.elements.count == 4,
                  let member = InspectionMember(key: row.elements[0]) else { throw invalidInspectionSnapshot() }
            return try InspectorRow(id: member, name: string(row.elements[1]),
                                    className: string(row.elements[2]), preview: string(row.elements[3]))
        }, path: path.elements.map(string), page: Int(page), pageCount: Int(pageCount), itemCount: Int(itemCount))
    }

    private func invalidInspectionSnapshot() -> SmalltalkError {
        SmalltalkError("Invalid inspector snapshot.")
    }

    func inspectionPrimitive(_ selector: String, _ args: [Value]) throws -> Value? {
        switch selector {
        case "inspectionClassOf:":
            return .string(inspectionClassName(args[0]))
        case "inspectionSummaryOf:":
            return .string(inspectionPreview(args[0], limit: 4096, multiline: true))
        case "inspectionSizeOf:":
            if case .array(let array) = args[0] { return .integer(Int64(array.elements.count)) }
            return .integer(Int64(inspectionFields(args[0]).count))
        case "inspectionMember:in:":
            guard let member = InspectionMember(key: args[0]),
                  let value = inspectionValue(member, in: args[1]) else { return .nilValue }
            return try array([value, .string(Self.previewText(member.name, limit: 160))])
        case "inspectionReference:sameAs:":
            return .boolean(sameInspectionReference(args[0], args[1]))
        case "inspectionRowsOf:from:to:":
            return try inspectionRows(of: args[0], from: Int(integer(args[1])), to: Int(integer(args[2])))
        default:
            return nil
        }
    }

    private func inspectionRows(of value: Value, from start: Int, to end: Int) throws -> Value {
        let fields = inspectionFields(value)
        let elements: [Value]?
        if case .array(let array) = value { elements = array.elements } else { elements = nil }
        let count = elements?.count ?? fields.count
        guard start > 0, start - 1 <= end, end <= count, end - (start - 1) <= 1024 else {
            throw SmalltalkError("Invalid inspector row range.")
        }
        return try withRoots([value]) { roots in
            let rows = try ((start - 1)..<end).map { offset in
                let member = elements == nil ? InspectionMember.field(fields[offset].name) : .index(offset + 1)
                let inspected = elements?[offset] ?? fields[offset].value
                let row = try array([
                    member.key, .string(Self.previewText(member.name, limit: 160)),
                    .string(inspectionClassName(inspected)), .string(inspectionPreview(inspected, limit: 96)),
                ])
                roots.add(row)
                return row
            }
            return try array(rows)
        }
    }

    private func inspectionFields(_ value: Value) -> [(name: String, value: Value)] {
        switch value {
        case .object(let object):
            return object.stClass.fields.map { ($0, object.fields[$0] ?? .nilValue) }
        case .classObject(let target):
            var fields = classOf(value).fields.compactMap { name in
                target.classState[name].map { (name, $0) }
            }
            if target.classState["superclass"] == nil {
                fields.insert(("superclass", target.superclass.map(Value.classObject) ?? .nilValue), at: 0)
            }
            return fields
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
            if let string = value.textContents { return inspectionPreview(.string(string), limit: limit, multiline: multiline) }
            text = "a \(inspectionClassName(value))"
        case .array(let array):
            text = "Array (\(array.elements.count) \(array.elements.count == 1 ? "element" : "elements"))"
        case .block(let block):
            text = "[Block · \(block.parameters.count) \(block.parameters.count == 1 ? "argument" : "arguments")]"
        case .classObject(let target):
            let name = Self.previewText(target.name, limit: limit)
            text = target.instanceClass == nil ? "\(name) class" : name
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
