import SmalltalkCore
import SwiftUI

struct SystemView: View {
    @Bindable var model: AppModel
    @State private var showingNewClass = false
    @State private var className = ""
    @State private var fieldNames = ""

    var body: some View {
        HSplitView {
            browserSidebar.frame(minWidth: 190, idealWidth: 220, maxWidth: 300)
            workspace.frame(minWidth: 510)
            inspector.frame(minWidth: 195, idealWidth: 230, maxWidth: 320)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                HStack(spacing: 8) {
                    Image(systemName: "square.stack.3d.up.fill").foregroundStyle(.tint)
                    Text("Smalltalk/80").fontWeight(.semibold)
                }
            }
            ToolbarItem(placement: .principal) {
                Picker("Ansicht", selection: $model.mode) {
                    ForEach(EditorMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).frame(width: 230)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Button("Zähler") { model.example(SmalltalkExamples.workspace) }
                    Button("Arrays und Blöcke") { model.example(SmalltalkExamples.collections) }
                    Button("Eine eigene Klasse") { model.example(SmalltalkExamples.classes) }
                    Button("Nachrichtenreihenfolge") { model.example(SmalltalkExamples.precedence) }
                } label: { Label("Beispiele", systemImage: "text.book.closed") }
                .help("Beispiel im Workspace öffnen")
                .disabled(model.isRunning)
                Button {
                    Task {
                        if model.mode == .workspace { await model.run() }
                        else { await model.acceptMethod() }
                    }
                } label: {
                    Label(model.mode == .workspace ? "Do it" : "Akzeptieren", systemImage: model.mode == .workspace ? "play.fill" : "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isRunning || model.mode == .browser && (model.isPrimitive || model.methodSource.isEmpty))
                .accessibilityIdentifier("executeButton")
                .help(model.mode == .workspace ? "Auswahl oder gesamten Workspace ausführen (⌘D)" : "Instanzmethode kompilieren (⌘S)")
            }
        }
        .sheet(isPresented: $showingNewClass) { newClassSheet }
    }

    private var browserSidebar: some View {
        VStack(spacing: 0) {
            HStack {
                sectionLabel("KLASSEN")
                Spacer()
                Text("\(model.classes.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Button { className = ""; fieldNames = ""; showingNewClass = true } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless).help("Neue Unterklasse von Object")
            }.padding(12)
            TextField("Klassen filtern", text: $model.search)
                .textFieldStyle(.roundedBorder).padding(.horizontal, 10).padding(.bottom, 8)
            List(model.filteredClasses, selection: Binding(get: { model.selectedClass }, set: { model.selectedClass = $0; model.chooseClass() })) { item in
                HStack(spacing: 7) {
                    Image(systemName: item.name == "Counter" ? "number.square" : "cube")
                        .foregroundStyle(item.name == "Counter" ? Color.accentColor : Color.secondary)
                    Text(item.name).font(.system(size: 12, design: .monospaced))
                }.tag(item.name)
            }.listStyle(.sidebar)
            Divider()
            HStack {
                sectionLabel("INSTANZMETHODEN")
                Spacer()
                Button { model.newMethod() } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless).disabled(model.selectedClass == nil).help("Neue Methode")
            }.padding(12)
            List(model.currentClass?.methods ?? [], selection: Binding(get: { model.selectedMethod }, set: { model.selectedMethod = $0; model.chooseMethod() })) { method in
                HStack(spacing: 7) {
                    Image(systemName: method.isPrimitive ? "gearshape" : "function").foregroundStyle(.secondary)
                    Text(method.selector).font(.system(size: 12, design: .monospaced))
                }.tag(method.selector)
            }.listStyle(.sidebar).frame(minHeight: 150, idealHeight: 230, maxHeight: 300)
        }.background(.background.secondary)
    }

    private var workspace: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(editorTitle).font(.title3.weight(.semibold))
                    Text(editorSubtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if model.isRunning { ProgressView().controlSize(.small) }
                Text(model.mode == .workspace ? "⌘D" : "⌘S")
                    .font(.caption.monospaced()).foregroundStyle(.secondary)
                    .padding(.horizontal, 7).padding(.vertical, 4).background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
            }.padding(16)
            Divider()
            VSplitView {
                Group {
                    if model.mode == .workspace {
                        CodeEditor(text: $model.workspace, selection: $model.workspaceSelection, isEditable: !model.isRunning, identifier: "workspaceEditor")
                    } else if !model.methodSource.isEmpty {
                        CodeEditor(text: $model.methodSource, selection: $model.methodSelection, isEditable: !model.isPrimitive && !model.isRunning, identifier: "methodEditor")
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "curlybraces").font(.system(size: 32)).foregroundStyle(.tertiary)
                            Text("Wähle eine Methode.").font(.headline)
                            Text("Oder füge deiner Klasse eine neue hinzu.").foregroundStyle(.secondary)
                            Button("Neue Methode") { model.newMethod() }.disabled(model.selectedClass == nil)
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }.frame(minHeight: 250)
                VStack(alignment: .leading, spacing: 0) {
                    resultView
                    Divider()
                    HStack {
                        sectionLabel("TRANSCRIPT")
                        Spacer()
                        Button("Leeren") { model.transcript = "" }.buttonStyle(.borderless).font(.caption)
                    }.padding(.horizontal, 14).padding(.vertical, 10)
                    ScrollViewReader { proxy in
                        ScrollView {
                            Text(model.transcript.isEmpty ? "Transcript show: 'Hallo'; cr." : model.transcript)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(model.transcript.isEmpty ? .secondary : .primary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14).padding(.bottom, 12)
                            Color.clear.frame(height: 1).id("end")
                        }.onChange(of: model.transcript) { proxy.scrollTo("end", anchor: .bottom) }
                    }
                    .accessibilityIdentifier("transcriptOutput")
                }.frame(minHeight: 160, idealHeight: 230)
            }
        }
    }

    private var resultView: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: model.error == nil ? "arrow.turn.down.right" : "exclamationmark.circle.fill")
                .foregroundStyle(model.error == nil ? Color.accentColor : Color.red)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 5) {
                Text(model.error == nil ? "ERGEBNIS" : "FEHLER").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                ScrollView(.vertical) {
                    Text(model.error ?? model.result)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(model.error == nil ? Color.primary : Color.red)
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: 68)
                .accessibilityIdentifier("evaluationResult")
            }
            Spacer(minLength: 0)
        }.padding(14).background(model.error == nil ? Color.accentColor.opacity(0.045) : Color.red.opacity(0.05))
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("OBJEKTE IM WORKSPACE").padding(14)
            if model.bindings.isEmpty {
                Text("Variablen und ihre Werte erscheinen nach dem Ausführen hier.")
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 14).padding(.bottom, 16)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(model.bindings) { binding in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(binding.name).font(.system(size: 12, weight: .semibold, design: .monospaced))
                            Text(binding.className).font(.system(size: 10)).foregroundStyle(.tint)
                            Text(binding.value).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.padding(.horizontal, 14).padding(.bottom, 16)
            }
            Divider()
            if let current = model.currentClass {
                VStack(alignment: .leading, spacing: 10) {
                    sectionLabel("KLASSE IM BROWSER")
                    Text(current.name).font(.system(.headline, design: .monospaced))
                    if let superclass = current.superclass {
                        Label(superclass, systemImage: "arrow.up").font(.caption).foregroundStyle(.secondary)
                    }
                    Text("Instanzvariablen").font(.caption.weight(.medium))
                    Text(current.fields.isEmpty ? "Keine" : current.fields.joined(separator: " · "))
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                    Text("\(current.methods.count) eigene Methoden").font(.caption).foregroundStyle(.secondary)
                }.padding(14)
            }
            Divider()
            VStack(alignment: .leading, spacing: 7) {
                sectionLabel("IMAGE")
                Text(model.imageURL?.lastPathComponent ?? "Noch kein Image gespeichert")
                    .font(.caption.weight(.medium)).lineLimit(2).textSelection(.enabled)
                    .accessibilityIdentifier("imageName")
                Text(model.imageHasChanges ? "Änderungen noch nicht gespeichert" : "Gespeicherter Stand")
                    .font(.caption).foregroundStyle(model.imageHasChanges ? Color.secondary : Color.accentColor)
                    .accessibilityIdentifier("imageStatus")
                Text("Ein Image erhält Klassen, akzeptierte Methoden, Objekte und den Workspace. Das zuletzt gespeicherte oder geöffnete Image wird beim Start geladen.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Image speichern") { Task { await model.saveImage() } }
                    .font(.caption).disabled(model.isRunning).accessibilityIdentifier("saveImageButton")
                Button("Sitzung zurücksetzen") { Task { await model.reset() } }
                    .font(.caption).buttonStyle(.borderless).disabled(model.isRunning)
            }.padding(14)
        }.background(.background.secondary)
    }

    private var editorTitle: String {
        if model.mode == .workspace { return model.workspaceURL?.lastPathComponent ?? "Workspace" }
        return "\(model.selectedClass ?? "Klasse") » \(model.selectedMethod ?? "Neue Methode")"
    }

    private var editorSubtitle: String {
        if model.mode == .browser { return model.isPrimitive ? "Primitive · in Swift implementiert" : "Instanzmethode · Änderungen mit ⌘S akzeptieren" }
        return model.workspaceSelection.length > 0 ? "Auswahl ausführen" : "Ausdruck markieren oder den gesamten Workspace ausführen"
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text).font(.system(size: 9, weight: .semibold)).tracking(0.8).foregroundStyle(.secondary)
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
                Button("Anlegen") {
                    Task { if await model.createClass(name: className, fields: fieldNames) { showingNewClass = false } }
                }.keyboardShortcut(.defaultAction).disabled(className.isEmpty || model.isRunning)
            }
        }.padding(24).frame(width: 420)
    }
}
