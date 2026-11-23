import Foundation
import Testing
@testable import SmalltalkCore

struct ObjectInspectorTests {
    private func openedInspector(in result: EvaluationResult) throws -> InspectorSnapshot {
        let inspectors = result.toolRequests.compactMap { request -> InspectorSnapshot? in
            guard case .openInspector(let snapshot) = request else { return nil }
            return snapshot
        }
        #expect(result.executionError == nil)
        #expect(inspectors.count == 1)
        return try #require(inspectors.first)
    }

    @Test func inspectingSourceEvaluatesOnceAndReflectsInheritedFieldsAndCycles() async throws {
        let session = SmalltalkSession()
        let setup = await session.evaluate("""
        Object subclass: #InspectBase instanceVariableNames: 'inherited'.
        InspectBase subclass: #InspectNode instanceVariableNames: 'next'.
        InspectBase compile: 'inherited: aValue inherited := aValue'.
        InspectNode compile: 'next: aNode next := aNode'.
        root := InspectNode new.
        root inherited: 17.
        other := InspectNode new.
        other inherited: 29.
        root next: other.
        other next: root.
        inspectionRuns := 0
        """)
        #expect(setup.error == nil)

        let result = await session.inspectSource("inspectionRuns := inspectionRuns + 1. root")
        let opened = try openedInspector(in: result)
        #expect(opened.className == "InspectNode")
        #expect(opened.rows.map(\.id) == [.field("inherited"), .field("next")])
        #expect(opened.rows.first?.preview == "17")

        let next = await session.inspect(opened.id, action: .follow(.field("next")))
        let nested = try #require(next)
        #expect(nested.id == opened.id)
        #expect(nested.className == "InspectNode")
        #expect(nested.rows.first?.preview == "29")
        #expect(nested.path == opened.path + ["next"])

        let ancestor = await session.inspect(opened.id, action: .follow(.field("next")))
        #expect(ancestor?.path == opened.path)
        #expect(ancestor?.rows.first?.preview == "17")
        _ = await session.inspect(opened.id, action: .follow(.field("next")))
        let back = await session.inspect(opened.id, action: .back)
        #expect(back?.path == opened.path)

        #expect(await session.evaluate("root inherited: 42. inspectionRuns").value == "1")
        let refreshed = await session.inspect(opened.id, action: .refresh)
        #expect(refreshed?.rows.first?.preview == "42")
    }

    @Test func inspectorPagesLargeArraysAndFollowsTheLastElement() async throws {
        let session = SmalltalkSession()
        let result = await session.inspectSource("items := Array new: 245. items at: 245 put: 73. items")
        let opened = try openedInspector(in: result)
        #expect(opened.className == "Array")
        #expect(opened.itemCount == 245)
        #expect(opened.rows.first?.id == .index(1))
        #expect(opened.rows.last?.id == .index(100))
        #expect(opened.page == 0)
        #expect(opened.pageCount == 3)

        let lastPage = await session.inspect(opened.id, action: .page(opened.pageCount - 1))
        #expect(lastPage?.rows.first?.id == .index(201))
        #expect(lastPage?.rows.last?.id == .index(245))
        #expect(lastPage?.rows.last?.preview == "73")

        let item = await session.inspect(opened.id, action: .follow(.index(245)))
        #expect(item?.className == "SmallInteger")
        #expect(item?.summary == "73")
        #expect(item?.rows.isEmpty == true)
        let back = await session.inspect(opened.id, action: .back)
        #expect(back?.page == 2)
        #expect(back?.rows.last?.id == .index(245))
    }

    @Test func toolPrimitiveKeepsTemporaryObjectAliveUntilInspectorCloses() async throws {
        let session = SmalltalkSession()
        let result = await session.evaluate("ToolVM inspect: (Counter new add: 43)")
        let opened = try openedInspector(in: result)
        #expect(opened.className == "Counter")

        let whileOpen = await session.collectGarbage()
        let refreshed = await session.inspect(opened.id, action: .refresh)
        #expect(refreshed?.rows.first { $0.id == .field("count") }?.preview == "43")

        await session.closeInspector(opened.id)
        #expect(await session.inspect(opened.id, action: .refresh) == nil)
        let afterClose = await session.collectGarbage()
        #expect(afterClose.liveObjects == whileOpen.liveObjects - 1)
    }

    @Test func inspectorRootsAreTransientAcrossImageLoadAndReset() async throws {
        let session = SmalltalkSession()
        let setup = await session.evaluate("Object subclass: #OnlyInspected instanceVariableNames: 'field'")
        #expect(setup.error == nil)
        let opened = try openedInspector(in: await session.inspectSource("OnlyInspected new"))
        let data = try await session.imageData()
        let image = try JSONDecoder().decode(ImageArchive.self, from: data)
        #expect(image.classes.contains { $0.name == "OnlyInspected" })
        #expect(!image.nodes.contains { node in
            guard case .object(let object) = node else { return false }
            return object.className == "OnlyInspected"
        })

        _ = try await session.loadImage(data)
        #expect(await session.inspect(opened.id, action: .refresh) == nil)
        let reopened = try openedInspector(in: await session.inspectSource("OnlyInspected new"))
        _ = await session.reset()
        #expect(await session.inspect(reopened.id, action: .refresh) == nil)
    }
}
