import Testing
@testable import SmalltalkCore

struct WorkspaceRecoveryTests {
    private func workspace(in result: EvaluationResult) throws -> ToolWindowInfo {
        try #require(result.windows.first { $0.kind == .workspace })
    }

    private func element(_ identifier: String, in root: UIElementInfo?) -> UIElementInfo? {
        guard let root else { return nil }
        if root.accessibilityID == identifier { return root }
        return root.children.lazy.compactMap { element(identifier, in: $0) }.first
    }

    private func recover(_ source: String, action: WorkspaceRecoveryAction = .evaluate,
                         in session: SmalltalkSession, from original: EvaluationResult) async throws -> EvaluationResult {
        let window = try workspace(in: original)
        return await session.recoverWorkspace(source: source, action: action, windowID: window.id,
                                              identity: window.identity, epoch: original.windowCommands.epoch)
    }

    private func breakWindowList(in session: SmalltalkSession) async throws -> EvaluationResult {
        let original = await session.snapshot()
        let broken = await session.evaluate("savedWindows := Desktop windows. Desktop model windows: nil")
        try #require(broken.error?.contains("valid window list") == true)
        return original
    }

    @Test func recoveryCommandsAcceptOnlyTheThreeWorkspaceEvaluationActions() {
        #expect(WorkspaceRecoveryAction(command: "doIt") == .evaluate)
        #expect(WorkspaceRecoveryAction(command: "printIt") == .print)
        #expect(WorkspaceRecoveryAction(command: "inspectIt") == .inspect)
        #expect(WorkspaceRecoveryAction(command: "debugIt") == nil)
        #expect(WorkspaceRecoveryAction(command: "acceptMethod") == nil)
    }

    @Test func aRetainedWorkspaceCanRestoreAnInvalidWindowList() async throws {
        let session = SmalltalkSession()
        let original = try await breakWindowList(in: session)
        let repaired = try await recover("Desktop model windows: savedWindows. 6 * 7", in: session, from: original)
        #expect(repaired.error == nil)
        #expect(repaired.value == "42")
        let restored = try workspace(in: repaired)
        #expect(restored.identity == (try workspace(in: original)).identity)
        #expect(element("evaluationResult", in: restored.content)?.text == "42")
        #expect(await session.evaluate("6 * 7").value == "42")
    }

    @Test func aRetainedWorkspaceCanRestoreItsInvalidControlTree() async throws {
        let session = SmalltalkSession()
        let original = await session.snapshot()
        let window = try workspace(in: original)
        let broken = await session.evaluate("""
            savedWorkspace := Desktop windowAt: \(window.id).
            savedContent := savedWorkspace content.
            savedWorkspace content: 42
            """)
        try #require(broken.error != nil)
        #expect(broken.windows.first { $0.id == window.id }?.content == nil)

        let repaired = try await recover("savedWorkspace content: savedContent. 20 + 22", in: session, from: original)
        #expect(repaired.error == nil)
        #expect(repaired.value == "42")
        #expect(try element("evaluationResult", in: workspace(in: repaired).content)?.text == "42")
    }

    @Test func recoveryReturnsTheEvaluationResultWhenTheDesktopRemainsInvalid() async throws {
        let session = SmalltalkSession()
        _ = await session.evaluate("recoveryRuns := 0")
        let original = try await breakWindowList(in: session)
        let result = try await recover("recoveryRuns := recoveryRuns + 1. 6 * 7", in: session, from: original)
        #expect(result.value == "42")
        #expect(result.executionError == nil)
        #expect(result.error?.contains("valid window list") == true)
        #expect(result.windows.isEmpty)
        #expect(await session.evaluate("recoveryRuns").value == "1")
    }

    @Test func recoveryPrintsAndInspectsTheSourceExactlyOnce() async throws {
        let printing = SmalltalkSession()
        _ = await printing.evaluate("recoveryRuns := 0")
        let printOriginal = try await breakWindowList(in: printing)
        let printed = try await recover("recoveryRuns := recoveryRuns + 1. 6 * 7", action: .print,
                                        in: printing, from: printOriginal)
        #expect(printed.value == "42")
        #expect(printed.executionError == nil)
        #expect(printed.transcript == "→ 42\n")
        #expect(await printing.evaluate("recoveryRuns").value == "1")

        let inspecting = SmalltalkSession()
        _ = await inspecting.evaluate("recoveryRuns := 0")
        let inspectOriginal = try await breakWindowList(in: inspecting)
        let inspected = try await recover("recoveryRuns := recoveryRuns + 1. Counter new add: recoveryRuns", action: .inspect,
                                          in: inspecting, from: inspectOriginal)
        #expect(inspected.value == "Object Inspector opened.")
        #expect(inspected.executionError == nil)
        let requests = inspected.toolRequests.compactMap { request -> InspectorSnapshot? in
            if case .openInspector(let snapshot) = request { return snapshot }
            return nil
        }
        #expect(requests.count == 1)
        #expect(requests.first?.rows.first { $0.id == .field("count") }?.preview == "1")
        #expect(await inspecting.evaluate("recoveryRuns").value == "1")
        #expect(await inspecting.snapshot().toolRequests.isEmpty)
    }

    @Test func recoveryReportsStepAndSourceLimitsWithoutPoisoningTheNextEvaluation() async throws {
        let session = SmalltalkSession()
        let original = try await breakWindowList(in: session)
        let loop = try await recover("[ true ] whileTrue: [ ]", in: session, from: original)
        #expect(loop.executionError?.contains("100,000 steps") == true)
        let tooLong = try await recover(String(repeating: " ", count: 65_537), in: session, from: original)
        #expect(tooLong.executionError?.contains("64 KiB") == true)
        let repaired = try await recover("Desktop model windows: savedWindows. 42", in: session, from: original)
        #expect(repaired.error == nil)
        #expect(repaired.value == "42")
    }

    @Test func aValidWorkspaceShowsRecoveryErrorsWithAFreshPresentationBudget() async throws {
        let session = SmalltalkSession()
        let original = await session.snapshot()
        let failed = try await recover("[ true ] whileTrue: [ ]", in: session, from: original)
        #expect(failed.executionError?.contains("100,000 steps") == true)
        #expect(try element("evaluationResult", in: workspace(in: failed).content)?.text.contains("100,000 steps") == true)
        let next = try await recover("6 * 7", in: session, from: original)
        #expect(next.error == nil)
        #expect(next.value == "42")
    }

    @Test func staleEpochsAndClosedWorkspacesCannotExecuteRecoverySource() async throws {
        let session = SmalltalkSession()
        let original = await session.snapshot()
        _ = await session.reset()
        _ = await session.evaluate("recoverySentinel := 73")
        _ = try await recover("recoverySentinel := 0", in: session, from: original)
        #expect(await session.evaluate("recoverySentinel").value == "73")

        let current = await session.snapshot()
        let window = try workspace(in: current)
        _ = await session.windowAction(.close(window.id))
        _ = try await recover("recoverySentinel := 0", in: session, from: current)
        #expect(await session.evaluate("recoverySentinel").value == "73")
    }

    @Test func detectableSameIDReplacementsCannotExecuteRecoverySourceEvenWhenInvalid() async throws {
        let session = SmalltalkSession()
        _ = await session.evaluate("recoverySentinel := 73")
        let original = await session.snapshot()
        let old = try workspace(in: original)
        let replaced = await session.evaluate("""
            (Desktop windowAt: \(old.id)) close.
            replacementWorkspace := Desktop openWorkspace.
            replacementWorkspace id: \(old.id); content: 42
            """)
        try #require(replaced.error != nil)
        let replacement = try #require(replaced.windows.first { $0.id == old.id })
        #expect(replacement.identity != old.identity)
        _ = try await recover("recoverySentinel := 0", in: session, from: original)
        #expect(await session.evaluate("recoverySentinel").value == "73")
    }
}
