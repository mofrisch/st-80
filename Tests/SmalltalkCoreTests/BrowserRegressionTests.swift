import Foundation
import Testing
@testable import SmalltalkCore

struct BrowserRegressionTests {
    private func element(_ identifier: String, in root: UIElementInfo?) -> UIElementInfo? {
        guard let root else { return nil }
        if root.accessibilityID == identifier { return root }
        return root.children.lazy.compactMap { element(identifier, in: $0) }.first
    }

    private func control(_ identifier: String, in result: EvaluationResult, windowID: Int64) throws -> UIElementInfo {
        try #require(element(identifier, in: result.windows.first { $0.id == windowID }?.content))
    }

    private func browser(in session: SmalltalkSession, side: MethodSide) async throws -> (Int64, EvaluationResult) {
        let initial = await session.snapshot()
        let window = try #require(initial.windows.first { $0.kind == .browser })
        guard side == .classSide else { return (window.id, initial) }
        let button = try control("classMethodSide", in: initial, windowID: window.id)
        let changed = await session.uiAction(.click(windowID: window.id, elementID: button.id))
        try #require(changed.error == nil)
        return (window.id, changed)
    }

    @Test(arguments: [MethodSide.instance, .classSide])
    func browserRejectsStaleMethodDraftsAndKeepsTheirText(side: MethodSide) async throws {
        let session = SmalltalkSession()
        let initialMethod = await session.compile("value ^ 1", in: "Counter", side: side)
        try #require(initialMethod.error == nil)
        let (windowID, opened) = try await browser(in: session, side: side)
        let methods = try control("methodList", in: opened, windowID: windowID)
        let selected = await session.uiAction(.select(windowID: windowID, elementID: methods.id, value: "value"))
        let editor = try control("methodEditor", in: selected, windowID: windowID)
        let accept = try control("executeButton", in: selected, windowID: windowID)
        let draft = "value ^ 111"
        _ = await session.uiAction(.text(windowID: windowID, elementID: editor.id, value: draft))

        let newer = await session.compile("value ^ 222", in: "Counter", side: side)
        try #require(newer.error == nil)
        #expect(try control("methodEditor", in: newer, windowID: windowID).text == draft)
        let rejected = await session.uiAction(.click(windowID: windowID, elementID: accept.id))
        #expect(rejected.error == nil)
        #expect(try control("evaluationResult", in: rejected, windowID: windowID).text.contains("method changed"))
        #expect(try control("methodEditor", in: rejected, windowID: windowID).text == draft)
        #expect(rejected.changes.map(\.id) == newer.changes.map(\.id))
        let expression = side == .instance ? "Counter new value" : "Counter value"
        #expect(await session.evaluate(expression).value == "222")

        let reopened = await session.uiAction(.select(windowID: windowID, elementID: methods.id, value: "value"))
        #expect(try control("methodEditor", in: reopened, windowID: windowID).text == "value ^ 222")
        _ = await session.uiAction(.text(windowID: windowID, elementID: editor.id, value: "value ^ 333"))
        let accepted = await session.uiAction(.click(windowID: windowID, elementID: accept.id))
        #expect(accepted.error == nil)
        #expect(await session.evaluate(expression).value == "333")
    }

    @Test(arguments: [MethodSide.instance, .classSide])
    func newMethodDraftCannotReplaceAMethodInstalledMeanwhile(side: MethodSide) async throws {
        let session = SmalltalkSession()
        let (windowID, opened) = try await browser(in: session, side: side)
        let newMethod = try control("newMethod", in: opened, windowID: windowID)
        let created = await session.uiAction(.click(windowID: windowID, elementID: newMethod.id))
        let editor = try control("methodEditor", in: created, windowID: windowID)
        let accept = try control("executeButton", in: created, windowID: windowID)
        let draft = "reviewDraft ^ 111"
        _ = await session.uiAction(.text(windowID: windowID, elementID: editor.id, value: draft))
        let newer = await session.compile("reviewDraft ^ 222", in: "Counter", side: side)
        try #require(newer.error == nil)

        let rejected = await session.uiAction(.click(windowID: windowID, elementID: accept.id))
        #expect(rejected.error == nil)
        #expect(try control("evaluationResult", in: rejected, windowID: windowID).text.contains("already exists"))
        #expect(try control("methodEditor", in: rejected, windowID: windowID).text == draft)
        #expect(rejected.changes.map(\.id) == newer.changes.map(\.id))
        let expression = side == .instance ? "Counter new reviewDraft" : "Counter reviewDraft"
        #expect(await session.evaluate(expression).value == "222")

        let oppositeSide: MethodSide = side == .instance ? .classSide : .instance
        let opposite = await session.compile("reviewOtherSide ^ 444", in: "Counter", side: oppositeSide)
        try #require(opposite.error == nil)
        _ = await session.uiAction(.text(windowID: windowID, elementID: editor.id, value: "reviewOtherSide ^ 555"))
        let accepted = await session.uiAction(.click(windowID: windowID, elementID: accept.id))
        #expect(accepted.error == nil)
        let sameSideExpression = side == .instance ? "Counter new reviewOtherSide" : "Counter reviewOtherSide"
        let oppositeExpression = side == .instance ? "Counter reviewOtherSide" : "Counter new reviewOtherSide"
        #expect(await session.evaluate(sameSideExpression).value == "555")
        #expect(await session.evaluate(oppositeExpression).value == "444")
    }

    @Test func browserMethodRenameCannotOverwriteAnExistingSelector() async throws {
        let session = SmalltalkSession()
        _ = await session.compile("reviewOriginal ^ 1", in: "Counter")
        _ = await session.compile("reviewDestination ^ 2", in: "Counter")
        let (windowID, opened) = try await browser(in: session, side: .instance)
        let methods = try control("methodList", in: opened, windowID: windowID)
        let selected = await session.uiAction(.select(windowID: windowID, elementID: methods.id, value: "reviewOriginal"))
        let editor = try control("methodEditor", in: selected, windowID: windowID)
        let accept = try control("executeButton", in: selected, windowID: windowID)
        _ = await session.uiAction(.text(windowID: windowID, elementID: editor.id, value: "reviewDestination ^ 3"))
        let rejected = await session.uiAction(.click(windowID: windowID, elementID: accept.id))
        #expect(try control("evaluationResult", in: rejected, windowID: windowID).text.contains("already exists"))
        #expect(await session.evaluate("Counter new reviewOriginal").value == "1")
        #expect(await session.evaluate("Counter new reviewDestination").value == "2")
    }

    @Test func methodHistoryIncludesOldVersionsDespiteUnrelatedRecentChanges() async throws {
        let session = SmalltalkSession()
        await session.worker.submit { runtime in
            let time = Date(timeIntervalSince1970: 1)
            var records = [
                ChangeInfo(id: "old-instance", sequence: 1, timestamp: time, kind: .method,
                           className: "Counter", selector: "value", superclass: nil, fields: nil,
                           source: "value ^ 17", methodSide: nil),
                ChangeInfo(id: "old-class", sequence: 2, timestamp: time, kind: .method,
                           className: "Counter", selector: "value", superclass: nil, fields: nil,
                           source: "value ^ 23", methodSide: .classSide),
                ChangeInfo(id: "other-selector", sequence: 3, timestamp: time, kind: .method,
                           className: "Counter", selector: "other", superclass: nil, fields: nil,
                           source: "other ^ 99", methodSide: nil),
            ]
            for sequence in 4...2004 {
                records.append(ChangeInfo(id: String(sequence), sequence: Int64(sequence), timestamp: time, kind: .method,
                                          className: "Object", selector: "value", superclass: nil, fields: nil,
                                          source: "value ^ 99", methodSide: nil))
            }
            runtime.journal = SourceJournal(records: records)
        }

        let opened = await session.windowAction(.showChanges(className: "Counter", selector: "value", side: .instance))
        try #require(opened.error == nil)
        let windowID = try #require(opened.windows.first { $0.kind == .changes }?.id)
        let list = try control("changesList", in: opened, windowID: windowID)
        #expect(list.historyEntries.map(\.id) == ["old-instance", "sources:Counter>>value"])
        let selected = await session.uiAction(.select(windowID: windowID, elementID: list.id, value: "old-instance"))
        let restore = try control("restoreChangeButton", in: selected, windowID: windowID)
        let restored = await session.uiAction(.click(windowID: windowID, elementID: restore.id))
        #expect(restored.error == nil)
        #expect(await session.evaluate("Counter new value").value == "17")

        let classHistory = await session.windowAction(.showChanges(className: "Counter", selector: "value", side: .classSide))
        #expect(classHistory.error == nil)
        #expect(try control("changesList", in: classHistory, windowID: windowID).historyEntries.map(\.id) == ["old-class"])
    }
}
