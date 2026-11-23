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
    @State private var isLoading = false
    @State private var isAvailable = true

    init(snapshot: InspectorSnapshot, session: SmalltalkSession) {
        self.session = session
        _snapshot = State(initialValue: snapshot)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            navigation
            Divider()
            if isAvailable {
                objectSummary
                if !snapshot.rows.isEmpty {
                    members
                }
                if snapshot.pageCount > 1 {
                    Divider()
                    pagination
                }
            } else {
                ContentUnavailableView("Inspection ended", systemImage: "magnifyingglass")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var navigation: some View {
        HStack {
            Button { perform(.back) } label: { Label("Back", systemImage: "chevron.left") }
                .disabled(!isAvailable || isLoading || snapshot.path.count < 2)
                .accessibilityIdentifier("inspectorBack")
            if snapshot.path.count > 1 {
                Text(snapshot.path.joined(separator: " › "))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer()
            Button { perform(.refresh) } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                .disabled(!isAvailable || isLoading)
                .accessibilityIdentifier("inspectorRefresh")
        }
        .padding(12)
    }

    private var objectSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(snapshot.className)
                .font(.headline)
                .accessibilityLabel(Text(snapshot.className))
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("inspectorClass")
            if snapshot.rows.isEmpty {
                ScrollView { summaryText }
            } else {
                summaryText.lineLimit(2)
            }
        }
        .padding(12)
    }

    private var summaryText: some View {
        Text(snapshot.summary)
            .font(.system(size: 13, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(Text(snapshot.summary))
            .accessibilityIdentifier("inspectorSummary")
    }

    private var members: some View {
        VStack(spacing: 0) {
            Divider()
            columns(name: "Member", value: "Value", className: "Class")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(snapshot.rows) { row in
                        Button { perform(.follow(row.id)) } label: {
                            columns(name: row.name, value: row.preview, className: row.className, showChevron: true)
                                .font(.system(size: 13, design: .monospaced))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(isLoading)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(row.name))
                        .accessibilityValue(Text("\(row.preview), \(row.className)"))
                        .accessibilityAddTraits(.isButton)
                        .accessibilityIdentifier("inspectorRow-\(row.name)")
                        Divider().padding(.leading, 12)
                    }
                }
            }
            .id([String(snapshot.page)] + snapshot.path)
            .accessibilityIdentifier("inspectorMembers")
        }
    }

    private func columns(name: String, value: String, className: String, showChevron: Bool = false) -> some View {
        HStack(spacing: 12) {
            Text(name).frame(width: 100, alignment: .leading)
            Text(value).frame(maxWidth: .infinity, alignment: .leading)
            Text(className).foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
                .opacity(showChevron ? 1 : 0)
                .accessibilityHidden(true)
        }
        .lineLimit(1)
    }

    private var pagination: some View {
        HStack {
            Button("Previous") { perform(.page(snapshot.page - 1)) }
                .disabled(isLoading || snapshot.page == 0)
                .accessibilityIdentifier("inspectorPreviousPage")
            Spacer()
            Text("\(snapshot.page + 1) of \(snapshot.pageCount)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("inspectorPage")
            Spacer()
            Button("Next") { perform(.page(snapshot.page + 1)) }
                .disabled(isLoading || snapshot.page >= snapshot.pageCount - 1)
                .accessibilityIdentifier("inspectorNextPage")
        }
        .padding(12)
    }

    private func perform(_ action: InspectorAction) {
        guard !isLoading, isAvailable else { return }
        isLoading = true
        Task {
            defer { isLoading = false }
            if let updated = await session.inspect(snapshot.id, action: action) {
                snapshot = updated
            } else {
                isAvailable = false
            }
        }
    }
}
