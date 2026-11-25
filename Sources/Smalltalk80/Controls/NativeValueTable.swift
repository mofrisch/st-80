import SmalltalkCore
import SwiftUI

struct NativeValueTable: View {
    let table: UIValueTableInfo
    let identifier: String
    let onOpen: ((String) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            columns(name: table.headings.name, value: Text(table.headings.value), className: table.headings.className)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.vertical, 6)
                .background(Color(nsColor: .controlBackgroundColor))
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(table.rows) { row in
                        rowView(row)
                        Divider().padding(.leading, CGFloat(table.horizontalPadding))
                    }
                }
            }
            .accessibilityIdentifier(identifier)
        }
    }

    @ViewBuilder
    private func rowView(_ row: UIValueRow) -> some View {
        let rowID = "\(table.rowIdentifierPrefix)-\(row.name)"
        if let onOpen {
            Button { onOpen(row.id) } label: {
                columns(name: row.name, value: Text(row.value), className: row.className, showsChevron: true)
                    .font(.system(size: 13, design: .monospaced))
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(row.name))
            .accessibilityValue(Text("\(row.value), \(row.className)"))
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier(rowID)
        } else {
            columns(name: row.name, value: Text(row.value).lineLimit(table.valueLines).textSelection(.enabled), className: row.className)
                .font(.system(size: 13, design: .monospaced))
                .padding(.vertical, 6)
                .accessibilityIdentifier(rowID)
        }
    }

    private func columns(name: String, value: some View, className: String, showsChevron: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: CGFloat(table.columnSpacing)) {
            Text(name).lineLimit(1).frame(width: CGFloat(table.nameWidth), alignment: .leading)
            value.frame(maxWidth: .infinity, alignment: .leading)
            Text(className).lineLimit(1).foregroundStyle(.secondary)
                .frame(width: CGFloat(table.classWidth), alignment: .leading)
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
        .padding(.horizontal, CGFloat(table.horizontalPadding))
    }
}
