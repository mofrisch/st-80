import SmalltalkCore
import SwiftUI

struct ChangesView: View {
    @Bindable var controller: AppController
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(controller.changeClassFilter.map { name in
                        let owner = controller.changeSideFilter?.displayName(for: name) ?? name
                        return "Versions: \(owner)\(controller.changeMethodFilter.map { " » \($0)" } ?? "")"
                    } ?? "Code Changes").font(.headline)
                    Text("Accepted code is logged immediately. The image stores the object graph.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("All Changes") {
                    controller.changeClassFilter = nil
                    controller.changeMethodFilter = nil
                    controller.changeSideFilter = nil
                }
                Button("Restore Version") { Task { await controller.restoreSelectedChange() } }
                    .disabled(controller.selectedChange == nil || controller.isRunning).accessibilityIdentifier("restoreChangeButton")
            }.padding(12)
            Divider()
            HSplitView {
                List(selection: $controller.selectedChange) {
                    ForEach(controller.filteredChanges) { change in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(change.side.displayName(for: change.className) + (change.selector.map { " » \($0)" } ?? " · Class Definition"))
                            HStack {
                                if change.sequence == 0 { Text("Shipped Baseline") }
                                else { Text(change.timestamp, format: .dateTime.year().month().day().hour().minute().second()) }
                                if change.sequence > controller.savedChangeSequence { Text("After Image Checkpoint").foregroundStyle(.orange) }
                            }.font(.caption)
                        }.tag(change.id)
                    }
                }.frame(minWidth: 250, idealWidth: 320).accessibilityIdentifier("changesList")
                ScrollView {
                    Text(controller.filteredChanges.first { $0.id == controller.selectedChange }?.source ?? "Select a change. You can restore later entries individually after restarting.")
                        .font(.system(size: 13, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                }.accessibilityIdentifier("changeSource")
            }
            Divider()
            if let path = controller.changesPath { Text(path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled).padding(8) }
            EvaluationView(value: controller.result, error: controller.error).frame(minHeight: 60, maxHeight: 100)
        }
    }
}

struct EvaluationView: View {
    let value: String
    let error: String?
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: error == nil ? "arrow.turn.down.right" : "exclamationmark.circle.fill")
                .foregroundStyle(error == nil ? Color.accentColor : Color.red)
            VStack(alignment: .leading, spacing: 5) {
                Text(error == nil ? "RESULT" : "ERROR").font(.caption).foregroundStyle(.secondary)
                ScrollView {
                    Text(error ?? value).font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(error == nil ? Color.primary : Color.red)
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }.accessibilityIdentifier("evaluationResult")
            }
        }.padding(12).background(Color.accentColor.opacity(0.04))
    }
}
