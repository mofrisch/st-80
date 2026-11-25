import Foundation
import Testing
@testable import SmalltalkCore

struct SourceJournalTests {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("st80-journal-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func redefine(_ name: String, superclass: String = "Object", fields: String = "", in session: SmalltalkSession) async -> EvaluationResult {
        let definition = "\(superclass) subclass: #\(name) instanceVariableNames: '\(fields)'"
            .replacingOccurrences(of: "'", with: "''")
        return await session.evaluate("ToolVM acceptDefinition: '\(definition)' in: \(name) basedOn: (ToolVM definitionOf: \(name))")
    }

    private func element(_ id: String, in root: UIElementInfo?) -> UIElementInfo? {
        guard let root else { return nil }
        if root.accessibilityID == id { return root }
        return root.children.lazy.compactMap { element(id, in: $0) }.first
    }

    @Test func changesWindowFiltersSelectsAndRestoresThroughItsControls() async throws {
        let session = SmalltalkSession()
        #expect(await session.compile("value ^ 51", in: "Counter").executionError == nil)
        #expect(await session.compile("value ^ 67", in: "Counter", side: .classSide).executionError == nil)
        let opened = await session.windowAction(.showChanges(className: "Counter", selector: "value", side: .instance))
        #expect(opened.error == nil)
        let window = try #require(opened.windows.first { $0.kind == .changes })

        let list = try #require(element("changesList", in: window.content))
        #expect(list.historyEntries.map(\.title) == ["Counter » value", "Counter » value"])
        #expect(list.historyEntries.first?.badge == "After Image Checkpoint")
        #expect(list.historyEntries.last?.subtitle == "Shipped Baseline")
        let baseline = try #require(list.historyEntries.last)
        let selected = await session.uiAction(.select(windowID: window.id, elementID: list.id, value: baseline.id))
        let selectedContent = selected.windows.first { $0.id == window.id }?.content
        let source = try #require(element("changeSource", in: selectedContent))
        #expect(source.children.first?.text == "value\n    ^ count")
        let restore = try #require(element("restoreChangeButton", in: selectedContent))
        #expect(restore.enabled)

        let restored = await session.uiAction(.click(windowID: window.id, elementID: restore.id))
        let restoredContent = restored.windows.first { $0.id == window.id }?.content
        #expect(element("evaluationResult", in: restoredContent)?.text == "Restored: Counter » value")
        #expect(await session.evaluate("Counter new value").value == "0")
        #expect(await session.evaluate("Counter value").value == "67")

        let all = try #require(element("allChangesButton", in: restoredContent))
        let cleared = await session.uiAction(.click(windowID: window.id, elementID: all.id))
        let allContent = cleared.windows.first { $0.id == window.id }?.content
        #expect(element("changesList", in: allContent)?.historyEntries.contains { $0.title == "Counter class » value" } == true)
        #expect(element("restoreChangeButton", in: allContent)?.enabled == false)
    }

    @Test func changesWindowKeepsItsSelectionAcrossEditsAndImageCheckpoints() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let image = folder.appendingPathComponent("HistorySelection.stimage")
        let session = SmalltalkSession()
        let initialSource = "value ^ 41"
        let initial = await session.compile(initialSource, in: "Counter")
        try #require(initial.executionError == nil)

        let opened = await session.windowAction(.showChanges(className: "Counter", selector: "value", side: .instance))
        let window = try #require(opened.windows.first { $0.kind == .changes })

        func control(_ id: String, in result: EvaluationResult) throws -> UIElementInfo {
            try #require(element(id, in: result.windows.first { $0.id == window.id }?.content))
        }

        let list = try control("changesList", in: opened)
        let record = try #require(list.historyEntries.first)
        #expect(record.badge == "After Image Checkpoint")
        let selected = await session.uiAction(.select(windowID: window.id, elementID: list.id, value: record.id))
        #expect(try control("changeSource", in: selected).children.first?.text == initialSource)

        let changed = await session.compile("value ^ 42", in: "Counter")
        try #require(changed.executionError == nil)
        let refreshed = try control("changesList", in: changed)
        #expect(refreshed.selection == record.id)
        #expect(refreshed.historyEntries.count == 3)
        #expect(refreshed.historyEntries[1].id == record.id)
        #expect(try control("changeSource", in: changed).children.first?.text == initialSource)

        try await session.saveImage(to: image, workspace: "", transcript: "")
        let afterSave = await session.evaluate("nil")
        let saved = try control("changesList", in: afterSave)
        #expect(saved.selection == record.id)
        #expect(saved.historyEntries.allSatisfy { $0.badge.isEmpty })
        #expect(try control("changeSource", in: afterSave).children.first?.text == initialSource)
        #expect(try control("restoreChangeButton", in: afterSave).enabled)
    }

    @Test func changesWindowSupportsTheFullJournalHistoryLimit() async throws {
        let session = SmalltalkSession()
        await session.worker.submit { runtime in
            let time = Date(timeIntervalSince1970: 1)
            let entries = (1...2000).map { sequence in
                ChangeInfo(id: String(sequence), sequence: Int64(sequence), timestamp: time, kind: .method,
                           className: "Counter", selector: "value", superclass: nil, fields: nil,
                           source: "value ^ 42", methodSide: nil)
            }
            runtime.journal = SourceJournal(records: entries)
        }
        let opened = await session.windowAction(.showChanges(className: "Counter", selector: "value", side: .instance))
        #expect(opened.error == nil)
        let root = try #require(opened.windows.first { $0.kind == .changes }?.content)
        let list = try #require(root.children.first { $0.kind == .split }?.children.first)
        #expect(list.historyEntries.count == 2001)
        #expect(list.historyEntries.first?.id == "2000")
        #expect(list.historyEntries.last?.subtitle == "Shipped Baseline")
    }

    @Test func superclassChangesProtectRetainedClassBlocksAndBothImageFormats() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("ClassBlocks.stimage")
        let log = folder.appendingPathComponent("ClassBlocks.changes")
        let session = SmalltalkSession()
        let setup = await session.evaluate("""
            Object subclass: #BlockHome instanceVariableNames: ''.
            BlockHome subclass: #BlockBranch instanceVariableNames: 'kept'.
            BlockBranch subclass: #BlockReceiver instanceVariableNames: 'extra'.
            BlockHome compileClass: 'callback ^ [ 42 ]'.
            live := BlockReceiver new.
            holder := Array new: 2.
            holder at: 1 put: BlockReceiver callback; at: 2 put: holder
            """)
        #expect(setup.error == nil)
        try await session.saveImage(to: url, workspace: "", transcript: "")
        let before = try Data(contentsOf: log)
        let rejected = await redefine("BlockBranch", fields: "kept added", in: session)
        #expect(rejected.value?.hasPrefix("#(false ") == true)
        #expect(rejected.value?.contains("BlockHome") == true)
        #expect(rejected.changes.map(\.id) == setup.changes.map(\.id))
        #expect(try Data(contentsOf: log) == before)
        #expect(rejected.classes.first { $0.name == "BlockBranch" }?.superclass == "BlockHome")
        #expect(rejected.classes.first { $0.name == "BlockReceiver" }?.fields == ["kept", "extra"])
        #expect(await session.evaluate("live printString").value == "'a BlockReceiver (kept: nil, extra: nil)'")
        #expect(await session.evaluate("(holder at: 1) value").value == "42")

        try await session.saveImage(to: url, workspace: "", transcript: "")
        let restored = SmalltalkSession()
        _ = try await restored.loadImage(session.imageData())
        #expect(await restored.evaluate("(holder at: 1) value").value == "42")
        _ = try await restored.loadImage(from: url)
        #expect(await restored.evaluate("(holder at: 1) value").value == "42")
        #expect(await restored.evaluate("(holder at: 2) == holder").value == "true")

        // The arena still retains the unreachable array. It must not veto edits.
        _ = await session.evaluate("holder := nil")
        let accepted = await redefine("BlockBranch", fields: "kept added", in: session)
        #expect(accepted.value?.hasPrefix("#(true ") == true)
        #expect(await session.evaluate("BlockBranch superclass name").value == "#Object")
        _ = try await restored.loadImage(session.imageData())
        #expect(await restored.evaluate("live printString").value == "'a BlockReceiver (kept: nil, added: nil, extra: nil)'")
    }

    @Test func fieldRemovalAndHistoryRestorationProtectCapturedBlockCode() async throws {
        let session = SmalltalkSession()
        let created = await session.evaluate("Object subclass: #FieldOwner instanceVariableNames: ''")
        let emptyLayout = try #require(created.changes.first { $0.className == "FieldOwner" && $0.kind == .classDefinition })
        #expect(await redefine("FieldOwner", fields: "count", in: session).value?.hasPrefix("#(true ") == true)
        let setup = await session.evaluate("""
            | captured |
            FieldOwner subclass: #FieldChild instanceVariableNames: ''.
            FieldOwner compile: 'deferred ^ [ count ]'.
            captured := FieldChild new deferred.
            heldBlock := [ captured ].
            FieldOwner compile: 'deferred ^ [ 42 ]'
            """)
        #expect(setup.error == nil)
        let rejected = await redefine("FieldOwner", in: session)
        #expect(rejected.value?.hasPrefix("#(false ") == true)
        #expect(rejected.value?.contains("instance variable count") == true)
        #expect(rejected.changes.map(\.id) == setup.changes.map(\.id))
        #expect(rejected.classes.first { $0.name == "FieldChild" }?.fields == ["count"])
        #expect(await session.evaluate("heldBlock value value").value == "nil")

        let history = await session.restoreChange(emptyLayout.id)
        #expect(history.error?.contains("instance variable count") == true)
        #expect(history.changes.map(\.id) == setup.changes.map(\.id))
        let restored = SmalltalkSession()
        _ = try await restored.loadImage(session.imageData())
        #expect(await restored.evaluate("heldBlock value value").value == "nil")
        _ = await session.evaluate("heldBlock := nil")
        #expect(await redefine("FieldOwner", in: session).value?.hasPrefix("#(true ") == true)
    }

    @Test(arguments: [
        "deferred ^ [ :count | [ count ] ] value: 42",
        "deferred ^ [ | count | count := 42. [ count ] ] value",
        "deferred ^ [ [ :count | count ] value: 42 ]",
        "deferred ^ [ | count | count := 42. count ]",
    ])
    func shadowedBlockVariablesDoNotPreventFieldRemoval(_ source: String) async throws {
        let session = SmalltalkSession()
        #expect(await session.evaluate("Object subclass: #ShadowOwner instanceVariableNames: 'count'").error == nil)
        #expect(await session.compile(source, in: "ShadowOwner").error == nil)
        #expect(await session.evaluate("heldBlock := ShadowOwner new deferred").error == nil)
        #expect(await session.compile("deferred ^ 0", in: "ShadowOwner").error == nil)
        #expect(await redefine("ShadowOwner", in: session).value?.hasPrefix("#(true ") == true)
        #expect(await session.evaluate("heldBlock value").value == "42")
    }

    @Test func activeClassMethodsCannotInvalidateBlocksCreatedAfterRedefinition() async throws {
        let session = SmalltalkSession()
        let setup = await session.evaluate("""
            Object subclass: #ActiveHome instanceVariableNames: ''.
            ActiveHome subclass: #ActiveReceiver instanceVariableNames: ''.
            attempt := nil
            """)
        #expect(setup.error == nil)
        let compiled = await session.compile("""
            moveAndReturnBlock
                attempt := ToolVM acceptDefinition: 'Object subclass: #ActiveReceiver instanceVariableNames: '''''
                    in: self basedOn: (ToolVM definitionOf: self).
                ^ [ 42 ]
            """, in: "ActiveHome", side: .classSide)
        #expect(compiled.error == nil)
        #expect(await session.evaluate("heldBlock := ActiveReceiver moveAndReturnBlock").error == nil)
        #expect(await session.evaluate("attempt at: 1").value == "false")
        #expect(await session.evaluate("ActiveReceiver superclass name").value == "#ActiveHome")
        let restored = SmalltalkSession()
        _ = try await restored.loadImage(session.imageData())
        #expect(await restored.evaluate("heldBlock value").value == "42")
    }

    @Test(arguments: ["receiver", "argument", "cascade", "collection", "super"])
    func inFlightMessagesAndCollectionResultsProtectClassBlocks(_ location: String) async throws {
        let session = SmalltalkSession()
        #expect(await session.evaluate("""
            Object subclass: #TransientHome instanceVariableNames: ''.
            TransientHome subclass: #TransientReceiver instanceVariableNames: ''.
            TransientHome compileClass: 'callback ^ [ 42 ]'.
            TransientHome compileClass: 'ignore: unused ^ [ 42 ]'.
            BlockClosure compile: 'after: ignored ^ self'.
            Object compile: 'first: aBlock second: ignored ^ aBlock'.
            attempt := nil
            """).error == nil)
        let change = "ToolVM acceptDefinition: 'Object subclass: #TransientReceiver instanceVariableNames: ''''' in: TransientReceiver basedOn: (ToolVM definitionOf: TransientReceiver)"
        let source: String
        switch location {
        case "receiver": source = "heldBlock := TransientReceiver callback after: (attempt := \(change))"
        case "argument": source = "heldBlock := Object new first: TransientReceiver callback second: (attempt := \(change))"
        case "cascade": source = "heldBlock := TransientReceiver callback yourself; after: (attempt := \(change))"
        case "collection": source = "holder := #(1 2) collect: [ :each | each = 1 ifTrue: [ TransientReceiver callback ] ifFalse: [ attempt := \(change). nil ] ]. heldBlock := holder at: 1"
        default:
            #expect(await session.compile("callbackAfterMove ^ super ignore: (attempt := \(change))", in: "TransientReceiver", side: .classSide).error == nil)
            source = "heldBlock := TransientReceiver callbackAfterMove"
        }
        #expect(await session.evaluate(source).error == nil)
        #expect(await session.evaluate("attempt at: 1").value == "false")
        #expect(await session.evaluate("TransientReceiver superclass name").value == "#TransientHome")
        let restored = SmalltalkSession()
        _ = try await restored.loadImage(session.imageData())
        #expect(await restored.evaluate("heldBlock value").value == "42")

        _ = await session.evaluate("heldBlock := nil. holder := nil")
        #expect(await session.evaluate("TransientReceiver callback after: (1 / 0)").error != nil)
        #expect(await redefine("TransientReceiver", in: session).value?.hasPrefix("#(true ") == true)
    }

    @Test func classDefinitionHistoryRestoresLayoutsAndRejectsFailedJournalWrites() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("Layout.stimage")
        let session = SmalltalkSession()
        let created = await session.evaluate("Object subclass: #Editable instanceVariableNames: 'count'. object := Editable new")
        let original = try #require(created.changes.first { $0.kind == .classDefinition && $0.className == "Editable" })
        let change = "ToolVM acceptDefinition: 'Object subclass: #Editable instanceVariableNames: ''count label''' in: Editable basedOn: (ToolVM definitionOf: Editable)"
        let edited = await session.evaluate(change)
        #expect(edited.changes.last?.fields == ["count", "label"])
        try await session.saveImage(to: url, workspace: "", transcript: "")
        let restored = SmalltalkSession()
        let loaded = try await restored.loadImage(from: url)
        #expect(loaded.evaluation.classes.first { $0.name == "Editable" }?.fields == ["count", "label"])
        let reverted = await restored.restoreChange(original.id)
        #expect(reverted.error == nil)
        #expect(reverted.classes.first { $0.name == "Editable" }?.fields == ["count"])
        #expect(reverted.changes.last?.fields == ["count"])

        let log = url.deletingPathExtension().appendingPathExtension("changes")
        let writer = try FileHandle(forWritingTo: log)
        defer { try? writer.close() }
        try writer.seekToEnd()
        try writer.write(contentsOf: Data("partial".utf8))
        let rejected = await restored.evaluate(change)
        #expect(rejected.value?.contains("outside this session") == true)
        #expect(rejected.classes.first { $0.name == "Editable" }?.fields == ["count"])
        #expect(rejected.changes.last?.id == reverted.changes.last?.id)
        #expect(await restored.evaluate("object printString").value == "'a Editable (count: nil)'")
    }


    @Test func classMethodsAndTheirLexicalSuperSurviveBothImageFormats() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("ClassSide.stimage")
        let log = url.deletingPathExtension().appendingPathExtension("changes")
        let session = SmalltalkSession()
        let definitions = await session.evaluate("""
            Object subclass: #SideBase instanceVariableNames: 'count'.
            SideBase subclass: #SideChild instanceVariableNames: ''.
            SideBase compile: 'answer ^ 3'.
            SideBase compileClass: 'answer ^ 40'.
            SideBase compileClass: 'make ^ super new'.
            SideChild compileClass: 'answer ^ super answer + 2'.
            SideChild compileClass: 'callback ^ [ super answer + 1 ]'.
            callback := SideChild callback
            """)
        #expect(definitions.error == nil)
        #expect(await session.evaluate("SideChild answer").value == "42")
        #expect(await session.evaluate("SideChild make answer").value == "3")
        #expect(await session.evaluate("SideBase respondsTo: #make").value == "true")
        #expect(await session.evaluate("SideChild classMethodNames").value == "#('answer' 'callback')")
        #expect(await session.evaluate("SideChild classMethodSourceAt: #answer asString").value == "'answer ^ super answer + 2'")
        #expect(await session.evaluate("SideChild new respondsTo: #callback").value == "false")

        try await session.saveImage(to: url, workspace: "", transcript: "")
        let records = try SourceJournal.read(log).records.filter { $0.className == "SideBase" && $0.selector == "answer" }
        #expect(records.map(\.side) == [.instance, .classSide])
        let classVersion = try #require(records.first { $0.side == .classSide })
        let portable = try await session.imageData()
        let reopened = SmalltalkSession()
        _ = try await reopened.loadImage(portable)
        #expect(await reopened.evaluate("callback value").value == "41")
        #expect(await reopened.evaluate("SideChild answer").value == "42")

        _ = try await reopened.loadImage(from: url)
        #expect(await reopened.evaluate("callback value").value == "41")
        #expect(await reopened.evaluate("SideChild make answer").value == "3")
        #expect(await reopened.compile("answer ^ 99", in: "SideBase", side: .classSide).error == nil)
        #expect(await reopened.evaluate("SideChild answer").value == "101")
        #expect(await reopened.restoreChange(classVersion.id).value == "Restored: SideBase class » answer")
        #expect(await reopened.evaluate("SideChild answer").value == "42")
        #expect(await reopened.evaluate("SideChild new answer").value == "3")
    }

    @Test func acceptedMethodsAreDurableBeforeSavingAndRejectedEditsNeverInstall() async throws {
        let folder = try directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let log = folder.appendingPathComponent("Unsaved.changes")
        let session = SmalltalkSession()
        try await session.startChangeLog(at: log)
        let accepted = await session.compile("answer ^ 42", in: "Counter")
        #expect(accepted.error == nil)
        let journal = try SourceJournal.read(log)
        #expect(journal.records.last?.source == "answer ^ 42")
        #expect(journal.records.last?.className == "Counter")
        let invalid = await session.compile("answer ^ (", in: "Counter")
        #expect(invalid.error != nil)
        #expect(try SourceJournal.read(log).sequence == journal.sequence)
        // An external writer invalidates the log's append position. An accepted
        // method must never become live when its durable journal write failed.
        let file = try FileHandle(forWritingTo: log)
        try file.seekToEnd(); try file.write(contentsOf: Data("external\n".utf8)); try file.close()
        let failed = await session.compile("answer ^ 73", in: "Counter")
        #expect(failed.error?.contains("outside") == true)
        let current = await session.evaluate("Counter new answer")
        #expect(current.value == "42")
    }

    @Test func fileImageUsesExecutableCodeAndExternalSourcesWhilePortableDataStillLoads() async throws {
        let folder = try directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("World.stimage")
        let session = SmalltalkSession()
        _ = await session.evaluate("Counter compile: 'answer ^ 42'. counter := Counter new. counter add: 7")
        try await session.saveImage(to: url, workspace: "counter value", transcript: "hello")
        let bytes = try Data(contentsOf: url)
        let saved = try JSONDecoder().decode(ImageFileArchive.self, from: bytes)
        #expect(saved.version == 6)
        #expect(saved.memory.classes.allSatisfy { $0.methods.isEmpty })
        #expect(saved.methods.contains { $0.className == "Counter" && $0.code.selector == "answer" && $0.changeID != nil })
        #expect(!String(decoding: bytes, as: UTF8.self).contains("answer ^ 42"))
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent(saved.sourcesFile).path))
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("World.changes").path))
        let restarted = SmalltalkSession()
        let loaded = try await restarted.loadImage(from: url)
        #expect(loaded.evaluation.error == nil)
        #expect(loaded.evaluation.savedChangeSequence == saved.checkpoint)
        let value = await restarted.evaluate("counter value + counter answer")
        #expect(value.value == "49")
        let portable = try await restarted.imageData()
        let copied = SmalltalkSession()
        _ = try await copied.loadImage(portable)
        let original = await copied.evaluate("counter answer")
        #expect(original.value == "42")
    }

    @Test func unsavedCodeAfterSnapshotIsReviewedAndRecoveredWithoutReplayingObjectMutations() async throws {
        let folder = try directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("Recovery.stimage")
        let original = SmalltalkSession()
        _ = await original.evaluate("Counter compile: 'answer ^ 1'. counter := Counter new. counter add: 10")
        try await original.saveImage(to: url, workspace: "counter value", transcript: "")
        let after = await original.evaluate("""
        Counter compile: 'answer ^ 2'.
        Object subclass: #RecoveredClass instanceVariableNames: ''.
        RecoveredClass compile: 'answer ^ 99'.
        counter add: 100
        """)
        #expect(after.error == nil)
        let restarted = SmalltalkSession()
        let loaded = try await restarted.loadImage(from: url)
        let state = await restarted.evaluate("counter value + counter answer")
        #expect(state.value == "11")
        #expect(!state.classes.contains { $0.name == "RecoveredClass" })
        let pending = loaded.evaluation.changes.filter { $0.sequence > loaded.evaluation.savedChangeSequence }
        #expect(pending.count == 3)
        for change in pending {
            let recovered = await restarted.restoreChange(change.id)
            #expect(recovered.error == nil)
        }
        let restored = await restarted.evaluate("counter value + counter answer + RecoveredClass new answer")
        #expect(restored.value == "111")
        try await restarted.saveImage(to: url, workspace: "", transcript: "")
        let third = SmalltalkSession()
        let savedAgain = try await third.loadImage(from: url)
        #expect(savedAgain.evaluation.changes.allSatisfy { $0.sequence <= savedAgain.evaluation.savedChangeSequence })
        let verified = await third.evaluate("RecoveredClass new answer")
        #expect(verified.value == "99")
    }

    @Test func interruptedFinalRecordIsIgnoredAndTheNextEditRepairsItsTail() async throws {
        let folder = try directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("Interrupted.stimage")
        let original = SmalltalkSession()
        try await original.saveImage(to: url, workspace: "", transcript: "")
        _ = await original.compile("answer ^ 17", in: "Counter")
        let log = url.deletingPathExtension().appendingPathExtension("changes")
        let file = try FileHandle(forWritingTo: log)
        try file.seekToEnd(); try file.write(contentsOf: Data("{\"incomplete\":".utf8)); try file.close()
        let restarted = SmalltalkSession()
        let loaded = try await restarted.loadImage(from: url)
        #expect(loaded.evaluation.changes.last?.source == "answer ^ 17")
        let edit = await restarted.compile("answer ^ 23", in: "Counter")
        #expect(edit.error == nil)
        let journal = try SourceJournal.read(log)
        #expect(journal.records.last?.source == "answer ^ 23")
        #expect(!String(decoding: try Data(contentsOf: log), as: UTF8.self).contains("incomplete"))
    }

    @Test func saveAsBranchesHistoryAndNeverOverwritesAnUnrelatedLog() async throws {
        let folder = try directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let first = folder.appendingPathComponent("First.stimage"), second = folder.appendingPathComponent("Second.stimage")
        let session = SmalltalkSession()
        _ = await session.compile("answer ^ 1", in: "Counter")
        try await session.saveImage(to: first, workspace: "", transcript: "")
        let firstLog = first.deletingPathExtension().appendingPathExtension("changes")
        let firstBytes = try Data(contentsOf: firstLog)
        try await session.saveImage(to: second, workspace: "", transcript: "")
        _ = await session.compile("answer ^ 2", in: "Counter")
        #expect(try Data(contentsOf: firstLog) == firstBytes)
        let firstID = try SourceJournal.read(firstLog).id
        let secondLog = try SourceJournal.read(second.deletingPathExtension().appendingPathExtension("changes"))
        #expect(firstID != secondLog.id)
        #expect(secondLog.records.last?.source == "answer ^ 2")
        let stranger = folder.appendingPathComponent("Stranger.changes")
        try Data("Do not overwrite".utf8).write(to: stranger)
        await #expect(throws: (any Error).self) { try await session.saveImage(to: folder.appendingPathComponent("Stranger.stimage"), workspace: "", transcript: "") }
        #expect(try String(contentsOf: stranger, encoding: .utf8) == "Do not overwrite")
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("Stranger.stimage").path))
    }

    @Test func missingOrMismatchedCompanionsLeaveTheCurrentWorldIntact() async throws {
        let folder = try directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("Missing.stimage")
        let donor = SmalltalkSession()
        try await donor.saveImage(to: url, workspace: "", transcript: "")
        let image = try JSONDecoder().decode(ImageFileArchive.self, from: Data(contentsOf: url))
        let sourcesURL = folder.appendingPathComponent(image.sourcesFile)
        let sources = try Data(contentsOf: sourcesURL)
        try FileManager.default.removeItem(at: sourcesURL)
        let current = SmalltalkSession()
        _ = await current.evaluate("kept := 42")
        await #expect(throws: (any Error).self) { try await current.loadImage(from: url) }
        let kept = await current.evaluate("kept")
        #expect(kept.value == "42")
        try sources.write(to: sourcesURL)
        let changesURL = folder.appendingPathComponent(image.changesFile)
        try FileManager.default.removeItem(at: changesURL)
        try SourceJournal().attach(to: changesURL)
        await #expect(throws: (any Error).self) { try await current.loadImage(from: url) }
        let stillKept = await current.evaluate("kept")
        #expect(stillKept.value == "42")
    }

    @Test func logsFromAnUnsavedWorldCanBeImportedWithoutExecutingThem() async throws {
        let folder = try directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("Unsaved.changes")
        let original = SmalltalkSession()
        try await original.startChangeLog(at: url)
        _ = await original.evaluate("Object subclass: #LostClass instanceVariableNames: ''. LostClass compile: 'answer ^ 73'")
        let fresh = SmalltalkSession()
        let activeLog = folder.appendingPathComponent("Active.changes")
        try await fresh.startChangeLog(at: activeLog)
        let imported = try await fresh.importChanges(from: url)
        #expect(!imported.classes.contains { $0.name == "LostClass" })
        #expect(imported.changes.count == 2)
        #expect(try SourceJournal.read(activeLog).records.map(\.id) == imported.changes.map(\.id))
        for record in imported.changes { #expect(await fresh.restoreChange(record.id).error == nil) }
        let recovered = await fresh.evaluate("LostClass new answer")
        #expect(recovered.value == "73")
    }

    @Test func importingBeyondTheRecordLimitDoesNotKeepTheRecordsThatFit() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("Incoming.changes")
        let incoming = SourceJournal()
        try incoming.append(kind: .method, className: "Counter", selector: "answer", source: "answer ^ 2")
        try incoming.append(kind: .method, className: "Counter", selector: "answer", source: "answer ^ 3")
        try incoming.attach(to: url)

        let session = SmalltalkSession()
        await session.worker.submit { runtime in
            let timestamp = Date(timeIntervalSince1970: 0)
            runtime.journal = SourceJournal(records: (1...99_999).map { sequence in
                ChangeInfo(id: "existing-\(sequence)", sequence: Int64(sequence), timestamp: timestamp,
                           kind: .method, className: "Counter", selector: "answer", superclass: nil,
                           fields: nil, source: "answer ^ 1", methodSide: nil)
            })
        }
        await #expect(throws: SmalltalkError.self) { try await session.importChanges(from: url) }
        let last = await session.worker.submit { $0.journal.records.last }
        #expect(last?.sequence == 99_999)
        #expect(last?.id == "existing-99999")
    }

    @Test func theShippedBaseVersionCanBeRestoredAndTheRestoreIsJournaled() async throws {
        let session = SmalltalkSession()
        let base = try #require(await session.baseVersion(of: "value", in: "Counter"))
        _ = await session.compile("value ^ 99", in: "Counter")
        let restored = await session.restoreChange(base.id)
        #expect(restored.error == nil)
        #expect(restored.changes.last?.source == base.source)
        let result = await session.evaluate("Counter new value")
        #expect(result.value == "0")
    }

    @Test func aSecondSessionCannotSilentlyOverwriteTheFirstSessionsLog() async throws {
        let folder = try directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("Shared.stimage")
        let first = SmalltalkSession()
        try await first.saveImage(to: url, workspace: "", transcript: "")
        let second = SmalltalkSession()
        _ = try await second.loadImage(from: url)
        #expect(await first.compile("answer ^ 42", in: "Counter").error == nil)
        let rejected = await second.compile("answer ^ 73", in: "Counter")
        #expect(rejected.error != nil)
        let log = try SourceJournal.read(url.deletingPathExtension().appendingPathExtension("changes"))
        #expect(log.records.last?.source == "answer ^ 42")
        let unchanged = await second.evaluate("Counter new respondsTo: #answer")
        #expect(unchanged.value == "false")
    }
}
