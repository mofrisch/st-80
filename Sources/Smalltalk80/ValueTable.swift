import SwiftUI

struct ValueTable<Row: Identifiable>: View {
    let rows: [Row]
    let name: KeyPath<Row, String>
    let value: KeyPath<Row, String>
    let className: KeyPath<Row, String>
    let identifier: String
    let rowIdentifierPrefix: String
    var isLoading = false
    var onOpen: ((Row) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            columns(name: "Name", value: Text("Value"), className: "Class")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.vertical, 6)
                .background(Color(nsColor: .controlBackgroundColor))
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        rowView(row)
                        Divider().padding(.leading, 12)
                    }
                }
            }
            .accessibilityIdentifier(identifier)
        }
    }

    @ViewBuilder
    private func rowView(_ row: Row) -> some View {
        let rowName = row[keyPath: name]
        let rowValue = row[keyPath: value]
        let rowClass = row[keyPath: className]
        if let onOpen {
            Button { onOpen(row) } label: {
                columns(name: rowName, value: Text(rowValue), className: rowClass, showsChevron: true)
                    .font(.system(size: 13, design: .monospaced))
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(rowName))
            .accessibilityValue(Text("\(rowValue), \(rowClass)"))
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("\(rowIdentifierPrefix)-\(rowName)")
        } else {
            columns(
                name: rowName,
                value: Text(rowValue).lineLimit(3).textSelection(.enabled),
                className: rowClass
            )
            .font(.system(size: 13, design: .monospaced))
            .padding(.vertical, 6)
            .accessibilityIdentifier("\(rowIdentifierPrefix)-\(rowName)")
        }
    }

    private func columns(
        name: String,
        value: some View,
        className: String,
        showsChevron: Bool = false
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(name).lineLimit(1).frame(width: 96, alignment: .leading)
            value.frame(maxWidth: .infinity, alignment: .leading)
            Text(className).lineLimit(1).foregroundStyle(.secondary)
                .frame(width: 108, alignment: .leading)
            if onOpen != nil {
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 10)
                    .opacity(showsChevron ? 1 : 0)
                    .accessibilityHidden(true)
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 12)
    }
}
