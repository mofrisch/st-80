import Foundation

public enum DebuggerPresentationPhase: String, Sendable {
    case paused, running, stopping
}

struct DebuggerPresentationDefinition: Sendable {
    let content: DebuggerClassDefinition?
    let window: DebuggerClassDefinition?

    init(content: STClass?, window: STClass?) {
        self.content = DebuggerClassDefinition(content)
        self.window = DebuggerClassDefinition(window)
    }
}

/// Method code is immutable. No values from a suspended activation cross over.
struct DebuggerClassDefinition: Sendable {
    let name: String
    let superclass: String
    let fields: [String]
    let methods: SelectorMap<Method>
    let classMethods: SelectorMap<Method>

    init?(_ source: STClass?) {
        guard let source, let parent = source.superclass else { return nil }
        name = source.name
        superclass = parent.name
        fields = source.ownFields
        methods = source.methods
        classMethods = source.classMethods
    }

    func materialize(in runtime: SmalltalkRuntime) throws -> STClass {
        guard let parent = runtime.classes[superclass] else {
            throw SmalltalkError("Debugger presentation superclass \(superclass) is unavailable.")
        }
        let copy = STClass(name, superclass: parent, fields: fields)
        copy.methods = methods
        copy.classMethods = classMethods
        return copy
    }
}

extension DebuggerSnapshot {
    private static let presentationWorker = InterpreterWorker()
    private static let recoveryWorker = InterpreterWorker()

    public func controlTree(selectedFrameID: Int? = nil,
                            phase: DebuggerPresentationPhase = .paused) async throws -> UIElementInfo {
        try Task.checkCancellation()
        return try await Self.presentationWorker.submitThrowing { runtime in
            try runtime.debuggerContent(for: self, selectedFrameID: selectedFrameID, phase: phase)
        }
    }

    package func windowInfo() async throws -> TransientWindowInfo {
        do {
            return try await Self.presentationWorker.submitThrowing { runtime in
                try runtime.debuggerWindowInfo(presentation?.window)
            }
        } catch {
            return try await Self.recoveryWorker.submitThrowing { runtime in
                try runtime.debuggerWindowInfo(nil)
            }
        }
    }

    package func commandPhase(after command: DebuggerCommand, from phase: DebuggerPresentationPhase) async throws -> DebuggerPresentationPhase? {
        try Task.checkCancellation()
        return try await Self.presentationWorker.submitThrowing { runtime in
            let windowClass = try runtime.debuggerWindowClass(presentation?.window)
            let hasError: Bool = if case .error = reason { true } else { false }
            runtime.steps = 0
            let next = try runtime.send(.classObject(windowClass), "phaseAfter:command:error:frameCount:", [
                .symbol(phase.rawValue), .symbol(command.rawValue), .boolean(hasError), .integer(Int64(frames.count)),
            ])
            if case .nilValue = next { return nil }
            guard case .symbol(let phase) = next, let result = DebuggerPresentationPhase(rawValue: phase) else {
                throw SmalltalkError("The debugger window returned an invalid phase.")
            }
            return result
        }
    }

    package func recoveryContent(message: String, phase: DebuggerPresentationPhase) async throws -> UIElementInfo {
        try Task.checkCancellation()
        return try await Self.recoveryWorker.submitThrowing { runtime in
            runtime.steps = 0
            let windowClass = try runtime.debuggerWindowClass(nil)
            let tree = try runtime.send(.classObject(windowClass), "fallbackFor:phase:", [
                runtime.debuggerLabel(message, maximum: 65_536), .symbol(phase.rawValue),
            ])
            guard let content = try runtime.projectContent(tree) else {
                throw SmalltalkError("The debugger recovery view is missing.")
            }
            return content
        }
    }
}

extension SmalltalkRuntime {
    fileprivate func debuggerWindowClass(_ definition: DebuggerClassDefinition?) throws -> STClass {
        guard let windowClass = try definition?.materialize(in: self) ?? classes["DebuggerWindow"] else {
            throw SmalltalkError("The debugger window class is missing.")
        }
        return windowClass
    }

    fileprivate func debuggerWindowInfo(_ definition: DebuggerClassDefinition?) throws -> TransientWindowInfo {
        steps = 0
        let windowClass = try debuggerWindowClass(definition)
        let window = try send(.classObject(windowClass), "new", [])
        return try projectTransientWindow(window)
    }

    fileprivate func debuggerContent(for snapshot: DebuggerSnapshot, selectedFrameID: Int?,
                                     phase: DebuggerPresentationPhase) throws -> UIElementInfo {
        guard let presenter = try snapshot.presentation?.content?.materialize(in: self) ?? classes["DebuggerPresentation"] else {
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
            let windowClass = try debuggerWindowClass(snapshot.presentation?.window)
            let key = try send(.classObject(windowClass), "selectionFor:requested:", [
                stack, selectedFrameID.map { .string(String($0)) } ?? .nilValue,
            ])
            let selected = if let name = key.textContents, let id = Int(name) {
                snapshot.frames.first(where: { $0.id == id })
            } else {
                nil as DebuggerFrame?
            }
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
        let limit = Self.valueTableRowLimit
        let overflow = frame.variables.count > limit
        let visible = frame.variables.prefix(overflow ? limit - 1 : limit)
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

    fileprivate func debuggerLabel(_ text: String, maximum: Int = 4_096) -> Value {
        guard text.utf8.count > maximum else { return .string(text) }
        // Leave room for an incomplete UTF-8 scalar's replacement and the ellipsis.
        return .string(String(decoding: text.utf8.prefix(maximum - 6), as: UTF8.self) + "…")
    }
}
