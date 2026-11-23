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
            if isAvailable {
                objectSummary
                if !snapshot.rows.isEmpty {
                    Divider()
                    ValueTable(rows: snapshot.rows, name: \.name, value: \.preview, className: \.className,
                               identifier: "inspectorMembers", rowIdentifierPrefix: "inspectorRow",
                               isLoading: isLoading) { row in
                        perform(.follow(row.id))
                    }
                    .id([String(snapshot.page)] + snapshot.path)
                }
                if snapshot.pageCount > 1 {
                    Divider()
                    pagination
                }
            } else {
                Divider()
                ContentUnavailableView("Inspection ended", systemImage: "magnifyingglass")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var navigation: some View {
        HStack(spacing: 10) {
            Button { perform(.back) } label: { Label("Back", systemImage: "chevron.left") }
                .disabled(!isAvailable || isLoading || snapshot.path.count < 2)
                .accessibilityIdentifier("inspectorBack")
            if isAvailable {
                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.className)
                        .font(.headline)
                        .lineLimit(1)
                        .accessibilityLabel(Text(snapshot.className))
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("inspectorClass")
                    if snapshot.path.count > 1 {
                        Text(snapshot.path.joined(separator: " › "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                }
            }
            Spacer()
            Button { perform(.refresh) } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                .disabled(!isAvailable || isLoading)
                .accessibilityIdentifier("inspectorRefresh")
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var objectSummary: some View {
        Group {
            if snapshot.rows.isEmpty {
                ScrollView { summaryText }
            } else {
                summaryText.lineLimit(2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var summaryText: some View {
        Text(snapshot.summary)
            .font(.system(size: 13, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(Text(snapshot.summary))
            .accessibilityIdentifier("inspectorSummary")
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
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
