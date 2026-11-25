import Foundation

public struct MethodInfo: Identifiable, Sendable {
    public var id: String { selector }
    public let selector: String
    public let source: String
    public let isPrimitive: Bool
}

public struct ClassInfo: Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let superclass: String?
    public let fields: [String]
    public let methods: [MethodInfo]
    public let classMethods: [MethodInfo]
}

public struct BindingInfo: Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let value: String
    public let className: String
}

public struct EvaluationResult: Sendable {
    public let value: String?
    public let error: String?
    /// A failed Smalltalk operation, distinct from an invalid native projection.
    public let executionError: String?
    public let windowProjectionError: String?
    public let transcript: String
    public let classes: [ClassInfo]
    public let bindings: [BindingInfo]
    public let windows: [ToolWindowInfo]
    public let activeWindowID: Int64?
    public let windowCommands: WindowCommandBatch
    public let toolRequests: [NativeToolRequest]
    public let changes: [ChangeInfo]
    public let savedChangeSequence: Int64
    public let changesPath: String?
}

extension SmalltalkRuntime {
    /// Execution boundaries may reconnect mounted bindings and invoke their
    /// accessors. snapshot(), drawing and image loading remain read-only.
    func finishEvaluation(value: String? = nil, error: String? = nil) -> EvaluationResult {
        var failure = error
        do {
            try refreshToolWindowsIfNeeded()
            try synchronizeMVCBindings()
            try synchronizeChangeHistory()
        } catch {
            failure = failure ?? error.localizedDescription
        }
        let requests = toolRequests
        toolRequests.removeAll()
        return snapshot(value: value, error: failure, requests: requests)
    }

    func snapshot(value: String? = nil, error: String? = nil, requests: [NativeToolRequest] = []) -> EvaluationResult {
        let infos = classes.values.sorted { $0.name < $1.name }.map { stClass in
            ClassInfo(name: stClass.name, superclass: stClass.superclass?.name, fields: stClass.fields,
                      methods: reflectedMethods(on: stClass, side: .instance), classMethods: reflectedMethods(on: stClass, side: .classSide))
        }
        let bindings = bindingInfos()
        let desktop = projectWindows()
        return EvaluationResult(value: value, error: error ?? desktop.error, executionError: error,
                                windowProjectionError: desktop.error, transcript: transcript, classes: infos,
                                bindings: bindings, windows: desktop.windows, activeWindowID: desktop.activeID,
                                windowCommands: projectWindowCommands(desktop.windows, active: desktop.activeID, valid: desktop.error == nil),
                                toolRequests: requests, changes: Array(journal.records.suffix(2000)),
                                savedChangeSequence: journal.savedSequence, changesPath: journal.url?.path)
    }
    func bindingInfos() -> [BindingInfo] {
        let bindings: [(String, Value)] = globals.keys.sorted().compactMap { name in
            guard let value = globals[name] else { return nil }
            if ["Desktop", "ToolVM", "TranscriptBuffer"].contains(name) { return nil }
            if case .classObject = value { return nil }
            if case .transcript = value { return nil }
            return (name, value)
        }
        var bytes = ValuePrinter.allBindingsBytes
        var values = ValuePrinter.allBindingsValues
        return bindings.enumerated().map { index, binding in
            let (name, value) = binding
            // Share the remaining space among all names so early aliases do
            // not consume the entire snapshot's preview budget.
            let byteLimit = min(ValuePrinter.bindingBytes, bytes / (bindings.count - index))
            let valueLimit = min(ValuePrinter.maximumValues, values / (bindings.count - index))
            var printer = ValuePrinter(maximumBytes: byteLimit, maximumValues: valueLimit)
            let preview = printer.print(value)
            bytes -= preview.utf8.count
            values -= valueLimit - printer.remainingValues
            return BindingInfo(name: name, value: preview, className: classOf(value).name)
        }
    }
}
