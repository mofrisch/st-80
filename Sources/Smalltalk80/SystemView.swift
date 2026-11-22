import SmalltalkCore
import SwiftUI

struct ToolContentView: View {
    @Bindable var model: AppModel
    let windowID: Int64

    var body: some View {
        Group {
            if let state = model.states[windowID] {
                switch state.kind {
                case .workspace: WorkspaceView(model: model, state: state)
                case .browser: SystemView(model: model)
                case .transcript: TranscriptView(model: model)
                }
            } else {
                Text("Fenster geschlossen").foregroundStyle(.secondary)
            }
        }.background(Color(nsColor: .windowBackgroundColor))
    }
}

struct WorkspaceView: View {
    @Bindable var model: AppModel
    @Bindable var state: ToolWindowState

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Workspace", systemImage: "doc.text").font(.headline)
                Spacer()
                Menu {
                    Button("Zähler") { Task { await model.example(SmalltalkExamples.workspace) } }
                    Button("Arrays und Blöcke") { Task { await model.example(SmalltalkExamples.collections) } }
                    Button("Eine eigene Klasse") { Task { await model.example(SmalltalkExamples.classes) } }
                    Button("Fenster öffnen") { Task { await model.example("window := Desktop openWorkspace.\nwindow title: 'Mein Workspace'.\nwindow text: '6 * 7'") } }
                } label: { Label("Beispiele", systemImage: "text.book.closed") }
                .disabled(model.isRunning)
                Button { Task { await model.run(windowID: state.id) } } label: { Label("Do it", systemImage: "play.fill") }
                    .buttonStyle(.borderedProminent).disabled(model.isRunning)
                    .accessibilityIdentifier("executeButton").help("Auswahl oder gesamten Workspace ausführen (⌘D)")
            }.padding(12)
            Divider()
            CodeEditor(text: $state.text, selection: $state.selection, isEditable: !model.isRunning, identifier: "workspaceEditor")
            Divider()
            EvaluationView(value: state.result, error: state.error ?? model.error)
                .frame(minHeight: 70, maxHeight: 120)
            Divider()
            ImageStatusView(model: model)
        }
    }
}

struct TranscriptView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Transcript", systemImage: "text.alignleft").font(.headline)
                Spacer()
                Button("Leeren") { model.transcript = "" }
            }.padding(12)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    Text(model.transcript.isEmpty ? "Transcript show: 'Hallo'; cr." : model.transcript)
                        .font(.system(size: 13, design: .monospaced)).textSelection(.enabled)
                        .foregroundStyle(model.transcript.isEmpty ? Color.secondary : Color.primary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                    Color.clear.frame(height: 1).id("end")
                }
                .accessibilityIdentifier("transcriptOutput")
                .onChange(of: model.transcript) { proxy.scrollTo("end", anchor: .bottom) }
            }
        }
    }
}

struct SystemView: View {
    @Bindable var model: AppModel
    @State private var showingNewClass = false
    @State private var className = ""
    @State private var fieldNames = ""

    var body: some View {
        HSplitView {
            sidebar.frame(minWidth: 190, idealWidth: 220, maxWidth: 280)
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(model.selectedClass ?? "Klasse") » \(model.selectedMethod ?? "Neue Methode")").font(.headline)
                        Text(model.isPrimitive ? "Primitive · in Swift implementiert" : "Instanzmethode · mit ⌘S akzeptieren").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { Task { await model.acceptMethod() } } label: { Label("Akzeptieren", systemImage: "checkmark") }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isRunning || model.isPrimitive || model.methodSource.isEmpty)
                        .accessibilityIdentifier("executeButton")
                }.padding(12)
                Divider()
                if model.methodSource.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "curlybraces").font(.system(size: 32)).foregroundStyle(.tertiary)
                        Text("Wähle eine Methode.").font(.headline)
                        Button("Neue Methode") { model.newMethod() }.disabled(model.selectedClass == nil)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    CodeEditor(text: $model.methodSource, selection: $model.methodSelection, isEditable: !model.isPrimitive && !model.isRunning, identifier: "methodEditor")
                }
                Divider()
                EvaluationView(value: model.result, error: model.error).frame(minHeight: 70, maxHeight: 120)
                Divider()
                ImageStatusView(model: model)
            }.frame(minWidth: 350)
            inspector.frame(minWidth: 180, idealWidth: 210, maxWidth: 280)
        }
        .sheet(isPresented: $showingNewClass) { newClassSheet }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack {
                sectionLabel("KLASSEN")
                Spacer()
                Text("\(model.classes.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Button { className = ""; fieldNames = ""; showingNewClass = true } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless).help("Neue Unterklasse von Object").disabled(model.isRunning)
            }.padding(12)
            TextField("Klassen filtern", text: $model.search).textFieldStyle(.roundedBorder).padding(.horizontal, 10).padding(.bottom, 8)
            List(model.filteredClasses, selection: Binding(get: { model.selectedClass }, set: { model.selectedClass = $0; model.chooseClass() })) { item in
                Label(item.name, systemImage: "cube").font(.system(size: 12, design: .monospaced)).tag(item.name)
            }.listStyle(.sidebar)
            Divider()
            HStack {
                sectionLabel("INSTANZMETHODEN")
                Spacer()
                Button { model.newMethod() } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless).disabled(model.selectedClass == nil || model.isRunning).help("Neue Methode")
            }.padding(12)
            List(model.currentClass?.methods ?? [], selection: Binding(get: { model.selectedMethod }, set: { model.selectedMethod = $0; model.chooseMethod() })) { method in
                Label(method.selector, systemImage: method.isPrimitive ? "gearshape" : "function")
                    .font(.system(size: 12, design: .monospaced)).tag(method.selector)
            }.listStyle(.sidebar).frame(minHeight: 150, idealHeight: 230, maxHeight: 300)
        }.background(.background.secondary)
    }

    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let current = model.currentClass {
                    sectionLabel("KLASSE IM BROWSER")
                    Text(current.name).font(.system(.headline, design: .monospaced))
                    if let superclass = current.superclass { Label(superclass, systemImage: "arrow.up").font(.caption).foregroundStyle(.secondary) }
                    Text("Instanzvariablen").font(.caption.weight(.medium))
                    Text(current.fields.isEmpty ? "Keine" : current.fields.joined(separator: " · "))
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                    Divider()
                }
                sectionLabel("GEMEINSAME VARIABLEN")
                ForEach(model.bindings) { binding in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(binding.name).font(.system(size: 12, weight: .semibold, design: .monospaced))
                        Text(binding.className).font(.system(size: 10)).foregroundStyle(.tint)
                        Text(binding.value).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
        }.background(.background.secondary)
    }

    private var newClassSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Eine neue Klasse").font(.title2.weight(.semibold))
            Text("Unterklasse von Object").foregroundStyle(.secondary)
            Form {
                TextField("Klassenname", text: $className, prompt: Text("Greeter"))
                TextField("Instanzvariablen", text: $fieldNames, prompt: Text("name age"))
            }
            if let error = model.error { Text(error).foregroundStyle(.red).font(.caption) }
            HStack {
                Spacer()
                Button("Abbrechen") { showingNewClass = false }.keyboardShortcut(.cancelAction)
                Button("Anlegen") { Task { if await model.createClass(name: className, fields: fieldNames) { showingNewClass = false } } }
                    .keyboardShortcut(.defaultAction).disabled(className.isEmpty || model.isRunning)
            }
        }.padding(24).frame(width: 420)
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
                sectionLabel(error == nil ? "ERGEBNIS" : "FEHLER")
                ScrollView {
                    Text(error ?? value).font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(error == nil ? Color.primary : Color.red)
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }.accessibilityIdentifier("evaluationResult")
            }
        }.padding(12).background(Color.accentColor.opacity(0.04))
    }
}

struct ImageStatusView: View {
    @Bindable var model: AppModel
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(model.imageURL?.lastPathComponent ?? "Noch kein Image gespeichert")
                    .font(.caption.weight(.medium)).accessibilityIdentifier("imageName")
                Text(model.imageHasChanges ? "Änderungen noch nicht gespeichert" : "Gespeicherter Stand")
                    .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("imageStatus")
            }
            Spacer()
            if model.isRunning { ProgressView().controlSize(.small) }
            Button("Image speichern") { Task { await model.saveImage() } }
                .disabled(model.isRunning).accessibilityIdentifier("saveImageButton")
        }.padding(12)
    }
}

private func sectionLabel(_ text: String) -> some View {
    Text(text).font(.system(size: 9, weight: .semibold)).tracking(0.8).foregroundStyle(.secondary)
}
