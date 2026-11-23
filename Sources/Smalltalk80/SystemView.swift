import SmalltalkCore
import SwiftUI

struct ToolContentView: View {
    @Bindable var controller: AppController
    let windowID: Int64

    var body: some View {
        Group {
            if let state = controller.states[windowID] {
                switch state.kind {
                case .workspace: WorkspaceView(controller: controller, state: state)
                case .browser: SystemView(controller: controller)
                case .transcript: TranscriptView(controller: controller)
                case .custom: UserInterfaceView(controller: controller, state: state)
                }
            } else {
                Text("Fenster geschlossen").foregroundStyle(.secondary)
            }
        }.background(Color(nsColor: .windowBackgroundColor))
    }
}

struct WorkspaceView: View {
    @Bindable var controller: AppController
    @Bindable var state: ToolWindowState

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Workspace", systemImage: "doc.text").font(.headline)
                Spacer()
                Menu {
                    Button("Zähler") { Task { await controller.example(SmalltalkExamples.workspace) } }
                    Button("Arrays und Blöcke") { Task { await controller.example(SmalltalkExamples.collections) } }
                    Button("Eine eigene Klasse") { Task { await controller.example(SmalltalkExamples.classes) } }
                    Button("Fenster öffnen") { Task { await controller.example("window := Desktop openWorkspace.\nwindow title: 'Mein Workspace'.\nwindow text: '6 * 7'") } }
                    Button("Eigene Oberfläche") { Task { await controller.example(SmalltalkExamples.userInterface) } }
                } label: { Label("Beispiele", systemImage: "text.book.closed") }
                .disabled(controller.isRunning)
                Button { Task { await controller.run(windowID: state.id) } } label: { Label("Do it", systemImage: "play.fill") }
                    .buttonStyle(.borderedProminent).disabled(controller.isRunning)
                    .accessibilityIdentifier("executeButton").help("Auswahl oder gesamten Workspace ausführen (⌘D)")
            }.padding(12)
            Divider()
            CodeEditor(text: $state.text, selection: $state.selection, isEditable: !controller.isRunning, identifier: "workspaceEditor")
            Divider()
            EvaluationView(value: state.result, error: state.error ?? controller.error)
                .frame(minHeight: 70, maxHeight: 120)
            Divider()
            ImageStatusView(controller: controller)
        }
    }
}

struct TranscriptView: View {
    @Bindable var controller: AppController

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Transcript", systemImage: "text.alignleft").font(.headline)
                Spacer()
                Button("Leeren") { controller.transcript = "" }
            }.padding(12)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    Text(controller.transcript.isEmpty ? "Transcript show: 'Hallo'; cr." : controller.transcript)
                        .font(.system(size: 13, design: .monospaced)).textSelection(.enabled)
                        .foregroundStyle(controller.transcript.isEmpty ? Color.secondary : Color.primary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                    Color.clear.frame(height: 1).id("end")
                }
                .accessibilityIdentifier("transcriptOutput")
                .onChange(of: controller.transcript) { proxy.scrollTo("end", anchor: .bottom) }
            }
        }
    }
}

struct SystemView: View {
    @Bindable var controller: AppController
    @State private var showingNewClass = false
    @State private var className = ""
    @State private var fieldNames = ""

    var body: some View {
        HSplitView {
            sidebar.frame(minWidth: 190, idealWidth: 220, maxWidth: 280)
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(controller.selectedClass ?? "Klasse") » \(controller.selectedMethod ?? "Neue Methode")").font(.headline)
                        Text(controller.isPrimitive ? "Primitive · in Swift implementiert" : "Instanzmethode · mit ⌘S akzeptieren").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { Task { await controller.acceptMethod() } } label: { Label("Akzeptieren", systemImage: "checkmark") }
                        .buttonStyle(.borderedProminent)
                        .disabled(controller.isRunning || controller.isPrimitive || controller.methodSource.isEmpty)
                        .accessibilityIdentifier("executeButton")
                }.padding(12)
                Divider()
                if controller.methodSource.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "curlybraces").font(.system(size: 32)).foregroundStyle(.tertiary)
                        Text("Wähle eine Methode.").font(.headline)
                        Button("Neue Methode") { controller.newMethod() }.disabled(controller.selectedClass == nil)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    CodeEditor(text: $controller.methodSource, selection: $controller.methodSelection, isEditable: !controller.isPrimitive && !controller.isRunning, identifier: "methodEditor")
                }
                Divider()
                EvaluationView(value: controller.result, error: controller.error).frame(minHeight: 70, maxHeight: 120)
                Divider()
                ImageStatusView(controller: controller)
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
                Text("\(controller.classes.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Button { className = ""; fieldNames = ""; showingNewClass = true } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless).help("Neue Unterklasse von Object").disabled(controller.isRunning)
            }.padding(12)
            TextField("Klassen filtern", text: $controller.search).textFieldStyle(.roundedBorder).padding(.horizontal, 10).padding(.bottom, 8)
            List(controller.filteredClasses, selection: Binding(get: { controller.selectedClass }, set: { controller.selectedClass = $0; controller.chooseClass() })) { item in
                Label(item.name, systemImage: "cube").font(.system(size: 12, design: .monospaced)).tag(item.name)
            }.listStyle(.sidebar)
            Divider()
            HStack {
                sectionLabel("INSTANZMETHODEN")
                Spacer()
                Button { controller.newMethod() } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless).disabled(controller.selectedClass == nil || controller.isRunning).help("Neue Methode")
            }.padding(12)
            List(controller.currentClass?.methods ?? [], selection: Binding(get: { controller.selectedMethod }, set: { controller.selectedMethod = $0; controller.chooseMethod() })) { method in
                Label(method.selector, systemImage: method.isPrimitive ? "gearshape" : "function")
                    .font(.system(size: 12, design: .monospaced)).tag(method.selector)
            }.listStyle(.sidebar).frame(minHeight: 150, idealHeight: 230, maxHeight: 300)
        }.background(.background.secondary)
    }

    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let current = controller.currentClass {
                    sectionLabel("KLASSE IM BROWSER")
                    Text(current.name).font(.system(.headline, design: .monospaced))
                    if let superclass = current.superclass { Label(superclass, systemImage: "arrow.up").font(.caption).foregroundStyle(.secondary) }
                    Text("Instanzvariablen").font(.caption.weight(.medium))
                    Text(current.fields.isEmpty ? "Keine" : current.fields.joined(separator: " · "))
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                    Divider()
                }
                sectionLabel("GEMEINSAME VARIABLEN")
                ForEach(controller.bindings) { binding in
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
            if let error = controller.error { Text(error).foregroundStyle(.red).font(.caption) }
            HStack {
                Spacer()
                Button("Abbrechen") { showingNewClass = false }.keyboardShortcut(.cancelAction)
                Button("Anlegen") { Task { if await controller.createClass(name: className, fields: fieldNames) { showingNewClass = false } } }
                    .keyboardShortcut(.defaultAction).disabled(className.isEmpty || controller.isRunning)
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
    @Bindable var controller: AppController
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(controller.imageURL?.lastPathComponent ?? "Noch kein Image gespeichert")
                    .font(.caption.weight(.medium)).accessibilityIdentifier("imageName")
                Text(controller.imageHasChanges ? "Änderungen noch nicht gespeichert" : "Gespeicherter Stand")
                    .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("imageStatus")
            }
            Spacer()
            if controller.isRunning { ProgressView().controlSize(.small) }
            Button("Image speichern") { Task { await controller.saveImage() } }
                .disabled(controller.isRunning).accessibilityIdentifier("saveImageButton")
        }.padding(12)
    }
}

private func sectionLabel(_ text: String) -> some View {
    Text(text).font(.system(size: 9, weight: .semibold)).tracking(0.8).foregroundStyle(.secondary)
}
