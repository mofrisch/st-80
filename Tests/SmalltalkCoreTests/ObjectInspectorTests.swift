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

        let secondPage = await session.inspect(opened.id, action: .nextPage)
        #expect(secondPage?.rows.first?.id == .index(101))
        let lastPage = await session.inspect(opened.id, action: .page(Int.max))
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
        let previous = await session.inspect(opened.id, action: .previousPage)
        #expect(previous?.rows.first?.id == .index(101))

        let edited = await session.compile("pageSize ^ 40", in: "InspectorModel")
        #expect(edited.executionError == nil)
        let refreshed = await session.inspect(opened.id, action: .refresh)
        #expect(refreshed?.pageCount == 7)
        #expect(refreshed?.rows.first?.id == .index(41))
        #expect(refreshed?.rows.last?.id == .index(80))
    }

    @Test func inspectorProjectsItsControlsFromTheRunningImage() async throws {
        let session = SmalltalkSession()
        let opened = try openedInspector(in: await session.inspectSource("Array new: 102"))

        func control(_ id: String, in root: UIElementInfo) -> UIElementInfo? {
            if root.accessibilityID == id { return root }
            return root.children.lazy.compactMap { control(id, in: $0) }.first
        }

        let root = try await session.inspectorContent(for: opened)
        let table = try #require(control("inspectorMembers", in: root))
        #expect(table.kind == .valueTable)
        #expect(table.command == "inspectMember")
        #expect(table.table?.rows.first?.name == "[1]")
        #expect(table.table?.rows.last?.name == "[100]")
        #expect(table.table?.headings.value == "Value")
        #expect(control("inspectorBack", in: root)?.enabled == false)
        #expect(control("inspectorPreviousPage", in: root)?.enabled == false)
        #expect(control("inspectorNextPage", in: root)?.enabled == true)

        let lastPage = try #require(await session.inspect(opened.id, action: .page(1)))
        let paginated = try await session.inspectorContent(for: lastPage)
        #expect(control("inspectorPage", in: paginated)?.text == "2 of 2")
        #expect(control("inspectorMembers", in: paginated)?.table?.rows.map(\.name) == ["[101]", "[102]"])
        #expect(control("inspectorNextPage", in: paginated)?.enabled == false)

        let updated = await session.compile("breadcrumbFor: path ^ 'Live path'", in: "InspectorPresentation", side: .classSide)
        #expect(updated.executionError == nil)
        let member = try #require(await session.inspect(opened.id, action: .follow(.index(102))))
        let nested = try await session.inspectorContent(for: member)
        #expect(control("inspectorBack", in: nested)?.enabled == true)
        #expect(control("inspectorSummary", in: nested)?.text == "nil")
        #expect(control("inspectorMembers", in: nested) == nil)
        #expect(nested.children[0].children[1].children.last?.text == "Live path")

        await session.closeInspector(opened.id)
        await #expect(throws: SmalltalkError.self) {
            _ = try await session.inspectorContent(for: opened)
        }
    }

    @Test func inspectorsKeepIndependentPathsAndRetainADetachedMember() async throws {
        let session = SmalltalkSession()
        let first = try openedInspector(in: await session.inspectSource("""
        inspectItems := Array new: 101.
        inspectItems at: 101 put: (Counter new add: 73; yourself).
        inspectItems
        """))
        let second = try openedInspector(in: await session.inspectSource("inspectItems"))
        #expect(first.id != second.id)

        let lastPage = try #require(await session.inspect(first.id, action: .nextPage))
        #expect(lastPage.page == 1)
        let detached = try #require(await session.inspect(first.id, action: .follow(.index(101))))
        #expect(detached.path == ["Array", "[101]"])
        let cleared = await session.evaluate("inspectItems at: 101 put: nil")
        try #require(cleared.executionError == nil)
        _ = await session.collectGarbage()

        let retained = try #require(await session.inspect(first.id, action: .refresh))
        #expect(retained.className == "Counter")
        #expect(retained.rows.first { $0.id == .field("count") }?.preview == "73")
        let untouched = try #require(await session.inspect(second.id, action: .refresh))
        #expect(untouched.path == ["Array"])
        #expect(untouched.page == 0)
        #expect(untouched.rows.first?.id == .index(1))

        await session.closeInspector(second.id)
        #expect(await session.inspect(second.id, action: .refresh) == nil)
        let back = try #require(await session.inspect(first.id, action: .back))
        #expect(back.path == ["Array"])
        #expect(back.page == 1)
        #expect(back.rows.map(\.id) == [.index(101)])
        #expect(back.rows.first?.preview == "nil")
    }

    @Test func toolPrimitiveKeepsTemporaryObjectAliveUntilInspectorCloses() async throws {
        let session = SmalltalkSession()
        let baseline = await session.collectGarbage()
        let result = await session.evaluate("ToolVM inspect: (Counter new add: 43)")
        let opened = try openedInspector(in: result)
        #expect(opened.className == "Counter")

        let whileOpen = await session.collectGarbage()
        let refreshed = await session.inspect(opened.id, action: .refresh)
        #expect(refreshed?.rows.first { $0.id == .field("count") }?.preview == "43")

        await session.closeInspector(opened.id)
        #expect(await session.inspect(opened.id, action: .refresh) == nil)
        let afterClose = await session.collectGarbage()
        #expect(whileOpen.liveObjects > baseline.liveObjects)
        #expect(afterClose.liveObjects == baseline.liveObjects)
    }

    @Test func anOlderImageUsesTheBundledInspectorModel() async throws {
        let previous = SmalltalkSession()
        await previous.worker.submit { runtime in
            for name in ["InspectorModel", "InspectorPresentation"] {
                runtime.globals.removeValue(forKey: name)
                runtime.classes.removeValue(forKey: name)
            }
        }
        let session = SmalltalkSession()
        _ = try await session.loadImage(previous.imageData())

        let opened = try openedInspector(in: await session.inspectSource("#(1 2)"))
        let member = try #require(await session.inspect(opened.id, action: .follow(.index(2))))
        #expect(member.summary == "2")
        #expect(member.path == ["Array", "[2]"])
        #expect(try await session.inspectorContent(for: member).kind == .column)
        #expect(await session.evaluate("ToolVM classNamed: 'InspectorModel'").value == "nil")
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
