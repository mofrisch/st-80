import Foundation

public enum DebuggerPresentationPhase: String, Sendable {
    case paused, running, stopping
}

/// Method code is immutable. No values from a suspended activation cross over.
struct DebuggerPresentationDefinition: Sendable {
    let superclass: String
    let fields: [String]
    let methods: [String: Method]
    let classMethods: [String: Method]

    init?(_ source: STClass?) {
        guard let source, let parent = source.superclass else { return nil }
        superclass = parent.name
        fields = source.ownFields
        methods = source.methods
        classMethods = source.classMethods
    }

    func materialize(in runtime: SmalltalkRuntime) throws -> STClass {
        guard let parent = runtime.classes[superclass] else {
            throw SmalltalkError("Debugger presentation superclass \(superclass) is unavailable.")
        }
        let copy = STClass("DebuggerPresentation", superclass: parent, fields: fields)
        copy.methods = methods
        copy.classMethods = classMethods
        return copy
    }
}

extension DebuggerSnapshot {
    private static let presentationWorker = InterpreterWorker()

    public func controlTree(selectedFrameID: Int? = nil,
                            phase: DebuggerPresentationPhase = .paused) async throws -> UIElementInfo {
        try Task.checkCancellation()
        return try await Self.presentationWorker.submitThrowing { runtime in
            try runtime.debuggerContent(for: self, selectedFrameID: selectedFrameID, phase: phase)
        }
    }
}

extension SmalltalkRuntime {
    fileprivate func debuggerContent(for snapshot: DebuggerSnapshot, selectedFrameID: Int?,
                                     phase: DebuggerPresentationPhase) throws -> UIElementInfo {
        guard let presenter = try snapshot.presentation?.materialize(in: self) ?? classes["DebuggerPresentation"] else {
            throw SmalltalkError("The debugger presentation is missing.")
        }

        steps = 0
        return try withRoots { roots in
            let stack = try array(snapshot.frames.map { frame in
                let row = try array([
                    .string(String(frame.id)), debuggerLabel(frame.title), .string(String(frame.line)), .string(""),
                ])
                roots.add(row)
                return row
            })
            roots.add(stack)
            let selected = snapshot.frames.first(where: { $0.id == selectedFrameID }) ?? snapshot.frames.first
            let frame = try selected.map { try debuggerFrameData($0, roots: roots) } ?? .nilValue
            roots.add(frame)
            let error: Value
            if case .error(let message) = snapshot.reason {
                error = debuggerLabel(message, maximum: 65_536)
            } else {
                error = .nilValue
            }

            let tree = try send(.classObject(presenter), "contentFor:frame:error:phase:", [
                stack, frame, error, .symbol(phase.rawValue),
            ])
            guard let content = try projectContent(tree) else {
                throw SmalltalkError("The debugger presentation must provide a control tree.")
            }
            return content
        }
    }

    private func debuggerFrameData(_ frame: DebuggerFrame, roots: RootScope) throws -> Value {
        let overflow = frame.variables.count > arrayLimit
        let visible = frame.variables.prefix(overflow ? arrayLimit - 1 : arrayLimit)
        var rows = try visible.enumerated().map { index, variable in
            let row = try array([
                .string(String(index)), debuggerLabel(variable.name),
                debuggerLabel(variable.value), debuggerLabel(variable.className),
            ])
            roots.add(row)
            return row
        }
        if overflow {
            let row = try array([
                .string("overflow"), .string("…"), .string("\(frame.variables.count - visible.count) more variables"), .string(""),
            ])
            roots.add(row)
            rows.append(row)
        }
        let variables = try array(rows)
        roots.add(variables)
        return try array([
            .string(String(frame.id)), debuggerLabel(frame.title), .string(frame.source),
            .integer(Int64(frame.line)), .integer(Int64(frame.column)), .string(frame.instruction), variables,
        ])
    }

    private func debuggerLabel(_ text: String, maximum: Int = 4_096) -> Value {
        guard text.utf8.count > maximum else { return .string(text) }
        // Leave room for an incomplete UTF-8 scalar's replacement and the ellipsis.
        return .string(String(decoding: text.utf8.prefix(maximum - 6), as: UTF8.self) + "…")
    }
}
