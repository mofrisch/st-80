import Foundation

public enum DebuggerCommand: String, Sendable {
    case stepInto, stepOver, stepOut, resume, stop
}

public enum DebuggerPauseReason: Equatable, Sendable {
    case entry, step, error(String)
}

public struct DebuggerVariable: Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let value: String
    public let className: String
}

public struct DebuggerFrame: Identifiable, Sendable {
    public let id: Int
    public let title: String
    public let source: String
    public let line: Int
    public let column: Int
    public let instruction: String
    public let variables: [DebuggerVariable]
}

public struct DebuggerSnapshot: Sendable {
    public let reason: DebuggerPauseReason
    /// The innermost activation comes first.
    public let frames: [DebuggerFrame]
    let presentation: DebuggerPresentationDefinition?
}

public enum DebuggerEvent: Sendable {
    case paused(DebuggerSnapshot)
    case finished(EvaluationResult)
}

/// A single-reader event stream and a command path independent of the VM queue.
public final class WorkspaceDebugSession: Sendable {
    public let events: AsyncStream<DebuggerEvent>
    private let channel: DebuggerChannel

    init() {
        let (events, continuation) = AsyncStream<DebuggerEvent>.makeStream(bufferingPolicy: .bufferingNewest(2))
        let channel = DebuggerChannel(continuation)
        self.events = events
        self.channel = channel
        continuation.onTermination = { [weak channel] termination in
            if case .cancelled = termination { channel?.send(.stop) }
        }
    }

    deinit { channel.send(.stop) }

    public func send(_ command: DebuggerCommand) { channel.send(command) }

    func start(source: String, workspaceID: Int64?, on worker: InterpreterWorker) {
        worker.submit(onCancellation: { [channel] in channel.send(.stop) }) { [channel] runtime in
            channel.finish(runtime.runDebugSource(source, workspaceID: workspaceID, channel: channel))
        }
    }
}

extension SmalltalkSession {
    public func debugSource(_ source: String, workspaceID: Int64? = nil) -> WorkspaceDebugSession {
        let session = WorkspaceDebugSession()
        session.start(source: source, workspaceID: workspaceID, on: worker)
        return session
    }
}

private struct DebuggerStopped: Error {}

/// Only snapshots, commands, and cancellation cross the worker boundary.
final class DebuggerChannel: @unchecked Sendable {
    private let continuation: AsyncStream<DebuggerEvent>.Continuation
    private let condition = NSCondition()
    private var awaitingCommand = false
    private var postmortem = false
    private var stopped = false
    private var finished = false
    private var command: DebuggerCommand?

    init(_ continuation: AsyncStream<DebuggerEvent>.Continuation) {
        self.continuation = continuation
    }

    func send(_ command: DebuggerCommand) {
        condition.lock()
        defer { condition.unlock() }
        guard !finished, !stopped else { return }
        if case .stop = command {
            stopped = true
        } else {
            guard awaitingCommand, !postmortem, self.command == nil else { return }
            self.command = command
        }
        condition.signal()
    }

    func checkStop() throws {
        condition.lock()
        defer { condition.unlock() }
        if stopped { throw DebuggerStopped() }
    }

    func pause(_ snapshot: DebuggerSnapshot) -> DebuggerCommand {
        condition.lock()
        if stopped {
            condition.unlock()
            return .stop
        }
        awaitingCommand = true
        if case .error = snapshot.reason { postmortem = true }
        condition.unlock()
        continuation.yield(.paused(snapshot))

        condition.lock()
        defer {
            awaitingCommand = false
            postmortem = false
            command = nil
            condition.unlock()
        }
        while !stopped && command == nil { condition.wait() }
        return stopped ? .stop : command ?? .stop
    }

    func finish(_ result: EvaluationResult) {
        condition.lock()
        finished = true
        condition.unlock()
        continuation.yield(.finished(result))
        continuation.finish()
    }
}

/// Lexical source is retained by live closures and is optional for image data
/// that predates the debugger. Method lookup is not used to guess block source.
struct DebuggerOrigin {
    let source: String
    var selector: String?
}

enum DebuggerFrameKind {
    case workspace, method, block
}

/// The worker keeps the activation and bytecode stacks live while it waits.
final class DebuggerExecution {
    private struct Frame {
        let id: Int
        let context: Context
        let kind: DebuggerFrameKind
        var instruction: BytecodeInstruction?
    }

    private struct Location: Equatable {
        let frame: Int
        let position: SourcePosition
    }

    private enum Stepping {
        case entry, into(Location), over(Location, depth: Int), out(depth: Int), running
    }

    private let channel: DebuggerChannel
    private var stepping = Stepping.entry
    private var frames: [Frame] = []
    private var nextFrame = 0
    private var reportedError = false

    init(_ channel: DebuggerChannel) { self.channel = channel }

    func enter(context: Context, kind: DebuggerFrameKind) {
        nextFrame += 1
        frames.append(Frame(id: nextFrame, context: context, kind: kind))
    }

    func leave() { frames.removeLast() }

    func before(_ instruction: BytecodeInstruction, runtime: SmalltalkRuntime) throws {
        let index = frames.count - 1
        frames[index].instruction = instruction
        guard instruction.operation.isDebuggerStep else { return }
        let location = Location(frame: frames[index].id, position: instruction.position)
        let depth = frames.count
        let reason: DebuggerPauseReason
        switch stepping {
        case .entry:
            reason = .entry
        case .into(let earlier) where earlier != location:
            reason = .step
        case .over(let earlier, let startingDepth) where depth < startingDepth || (depth == startingDepth && earlier != location):
            reason = .step
        case .out(let startingDepth) where depth < startingDepth:
            reason = .step
        default:
            return
        }
        switch channel.pause(snapshot(reason, runtime: runtime)) {
        case .stepInto: stepping = .into(location)
        case .stepOver: stepping = .over(location, depth: depth)
        case .stepOut: stepping = .out(depth: depth)
        case .resume: stepping = .running
        case .stop: throw DebuggerStopped()
        }
    }

    func report(_ error: Error, at instruction: BytecodeInstruction, runtime: SmalltalkRuntime) {
        guard !reportedError, !(error is DebuggerStopped), !(error is ReturnSignal) else { return }
        reportedError = true
        frames[frames.count - 1].instruction = instruction
        _ = channel.pause(snapshot(.error(error.localizedDescription), runtime: runtime))
    }

    private func snapshot(_ reason: DebuggerPauseReason, runtime: SmalltalkRuntime) -> DebuggerSnapshot {
        DebuggerSnapshot(reason: reason, frames: frames.reversed().map { frame in
            let context = frame.context
            let owner = context.homeClass.map { context.methodSide.displayName(for: $0.name) } ?? "Workspace"
            let home = context.debuggerOrigin?.selector.map { "\(owner) » \($0)" } ?? owner
            let title = frame.kind == .block ? "Block in \(home)" : home
            return DebuggerFrame(id: frame.id, title: title, source: context.debuggerOrigin?.source ?? "",
                                 line: frame.instruction?.position.line ?? 1, column: frame.instruction?.position.column ?? 1,
                                 instruction: String((frame.instruction?.operation.disassemblyText ?? "").prefix(240)),
                                 variables: variables(in: context, runtime: runtime))
        }, presentation: DebuggerPresentationDefinition(runtime.classes["DebuggerPresentation"]))
    }

    private func variables(in context: Context, runtime: SmalltalkRuntime) -> [DebuggerVariable] {
        var values = ["self": context.receiver]
        var scope: Environment? = context.environment
        while let current = scope {
            values.merge(current.values) { inner, _ in inner }
            scope = current.parent
        }
        if case .object(let receiver) = context.receiver {
            values.merge(receiver.fields) { local, _ in local }
        }
        if context.isWorkspace {
            for (name, value) in runtime.globals where values[name] == nil {
                if case .classObject = value { continue }
                if case .transcript = value { continue }
                if ["Desktop", "ToolVM", "TranscriptBuffer"].contains(name) { continue }
                values[name] = value
            }
        }
        // Object previews are shallow so even cyclic collections remain cheap
        // to inspect while execution is suspended.
        return values.keys.sorted().compactMap { name in
            guard let value = values[name] else { return nil }
            return DebuggerVariable(name: name, value: runtime.inspectionPreview(value, limit: 128),
                                    className: runtime.inspectionClassName(value))
        }
    }
}

private extension BytecodeOperation {
    var isDebuggerStep: Bool {
        switch self {
        case .pushLiteral, .load, .store, .send, .makeBlock:
            return true
        case .pop, .duplicate, .prepareSend, .discardReceiverBelowResult, .checkReturn, .returnFromHome, .finish:
            return false
        }
    }
}

extension SmalltalkRuntime {
    fileprivate func runDebugSource(_ source: String, workspaceID: Int64?, channel: DebuggerChannel) -> EvaluationResult {
        if workspaceID == nil { transcript = "" }
        let workspaceIdentity = workspaceID.flatMap { projectedWindow(withID: $0)?.nativeID }
        steps = 0
        depth = 0
        catalogDirty = true
        evaluatingToolSource = true
        debugger = DebuggerExecution(channel)
        debuggerCancellation = channel
        let result: (value: String?, error: String?)
        do {
            try channel.checkStop()
            guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw SmalltalkError("Enter an expression to debug.")
            }
            let value = try evaluate(source)
            try channel.checkStop()
            result = (printValue(value), nil)
        } catch is DebuggerStopped {
            result = (nil, "Debugging stopped.")
        } catch {
            result = (nil, error.localizedDescription)
        }
        debugger = nil
        debuggerCancellation = nil
        evaluatingToolSource = false
        steps = 0
        depth = 0

        if let workspaceID, let workspace = projectedWindow(withID: workspaceID),
           workspace.nativeID == workspaceIdentity, isUIClass(workspace.stClass, named: "WorkspaceWindow") {
            do {
                try withRoots([.object(workspace)]) { _ in
                    let outcome = try array([.boolean(result.error == nil), .string(result.value ?? result.error ?? "")])
                    _ = try send(.object(workspace), "result:", [outcome])
                }
            } catch {
                return finishEvaluation(value: result.value, error: result.error ?? error.localizedDescription)
            }
        }
        return finishEvaluation(value: result.value, error: result.error)
    }
}
