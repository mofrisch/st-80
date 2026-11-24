import AppKit
import Observation
import SmalltalkCore
import SwiftUI

@MainActor
@Observable
final class NativeInspectorWindows {
    private struct Entry {
        let window: NSWindow
        let delegate: WindowDelegate
    }

    @ObservationIgnored private let session: SmalltalkSession
    @ObservationIgnored private var entries: [UUID: Entry] = [:]
    private var keyInspector: UUID?

    var hasKeyWindow: Bool { keyInspector != nil }

    init(session: SmalltalkSession) { self.session = session }

    func open(_ snapshot: InspectorSnapshot) {
        let id = snapshot.id
        if let entry = entries[id] {
            entry.window.makeKeyAndOrderFront(nil)
            return
        }

        let size = NSSize(width: 540, height: 440)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Object Inspector"
        window.identifier = NSUserInterfaceItemIdentifier("objectInspector-\(id.uuidString)")
        window.setAccessibilityIdentifier("objectInspector")
        window.setAccessibilityLabel(window.title)
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.tabbingMode = .disallowed
        let hosting = NSHostingController(rootView: ObjectInspectorView(snapshot: snapshot, session: session))
        hosting.sizingOptions = []
        window.contentViewController = hosting
        window.contentMinSize = NSSize(width: 380, height: 250)
        window.setContentSize(size)
        window.center()

        let delegate = WindowDelegate(id: id, windows: self)
        window.delegate = delegate
        entries[id] = Entry(window: window, delegate: delegate)
        NSApp.addWindowsItem(window, title: window.title, filename: false)
        window.makeKeyAndOrderFront(nil)
    }

    func closeAll() {
        let windows = entries.values.map(\.window)
        for window in windows { window.close() }
    }

    private func closed(_ id: UUID) {
        guard let entry = entries.removeValue(forKey: id) else { return }
        if keyInspector == id { keyInspector = nil }
        entry.window.delegate = nil
        NSApp.removeWindowsItem(entry.window)
        Task { [session] in await session.closeInspector(id) }
    }

    @MainActor
    private final class WindowDelegate: NSObject, NSWindowDelegate {
        let id: UUID
        weak var windows: NativeInspectorWindows?

        init(id: UUID, windows: NativeInspectorWindows) {
            self.id = id
            self.windows = windows
        }

        func windowDidBecomeKey(_ notification: Notification) { windows?.keyInspector = id }

        func windowDidResignKey(_ notification: Notification) {
            if windows?.keyInspector == id { windows?.keyInspector = nil }
        }

        func windowWillClose(_ notification: Notification) { windows?.closed(id) }
    }
}

private struct ObjectInspectorView: View {
    let session: SmalltalkSession
    @State private var snapshot: InspectorSnapshot
    @State private var content: UIElementInfo?
    @State private var isLoading = true
    @State private var errorMessage: String?

    init(snapshot: InspectorSnapshot, session: SmalltalkSession) {
        self.session = session
        _snapshot = State(initialValue: snapshot)
    }

    var body: some View {
        Group {
            if let errorMessage {
                ContentUnavailableView(errorMessage, systemImage: "magnifyingglass")
            } else if let content {
                UIElementView(host: .snapshot(isLoading: isLoading, click: click, select: select), element: content)
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .task { await present(snapshot) }
    }

    private func click(_ control: UIElementInfo) {
        switch control.command {
        case "inspectBack": perform(.back)
        case "inspectRefresh": perform(.refresh)
        case "inspectPreviousPage": perform(.previousPage)
        case "inspectNextPage": perform(.nextPage)
        default: break
        }
    }

    private func select(_ control: UIElementInfo, row: String) {
        guard control.command == "inspectMember", let index = Int(row), snapshot.rows.indices.contains(index) else { return }
        perform(.follow(snapshot.rows[index].id))
    }

    private func perform(_ action: InspectorAction) {
        guard !isLoading, errorMessage == nil else { return }
        isLoading = true
        Task {
            guard let updated = await session.inspect(snapshot.id, action: action) else {
                errorMessage = "Inspection ended"
                isLoading = false
                return
            }
            await present(updated)
        }
    }

    private func present(_ updated: InspectorSnapshot) async {
        defer { isLoading = false }
        do {
            let tree = try await session.inspectorContent(for: updated)
            guard !Task.isCancelled else { return }
            snapshot = updated
            content = tree
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
