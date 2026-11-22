import AppKit
import SmalltalkCore
import SwiftUI
import UniformTypeIdentifiers

enum EditorMode: String, CaseIterable {
    case workspace = "Workspace"
    case browser = "Browser"
}

@MainActor
@Observable
final class AppModel {
    var mode = EditorMode.workspace
    var workspace = SmalltalkExamples.workspace {
        didSet { if workspace != oldValue { imageHasChanges = true } }
    }
    var workspaceSelection = NSRange(location: 0, length: 0)
    var methodSource = ""
    var methodSelection = NSRange(location: 0, length: 0)
    var selectedClass: String? = "Counter"
    var selectedMethod: String?
    var classes: [ClassInfo] = []
    var bindings: [BindingInfo] = []
    var transcript = "" {
        didSet { if transcript != oldValue { imageHasChanges = true } }
    }
    var result = "Bereit. Markiere einen Ausdruck oder führe den Workspace aus."
    var error: String?
    var isRunning = false
    var search = ""
    var workspaceURL: URL?
    var imageURL: URL?
    var imageHasChanges = true
    private let session = SmalltalkSession()
    private let preferences: UserDefaults
    private var hasLoaded = false
    private static let lastImageKey = "lastImagePath"
    private static var imageType: UTType { UTType(filenameExtension: "stimage", conformingTo: .data) ?? .data }

    init() {
        let suite = ProcessInfo.processInfo.environment["ST80_PREFERENCES_SUITE"]
        preferences = suite.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    var currentClass: ClassInfo? { classes.first { $0.name == selectedClass } }
    var currentMethod: MethodInfo? { currentClass?.methods.first { $0.selector == selectedMethod } }
    var isPrimitive: Bool { currentMethod?.isPrimitive == true }
    var filteredClasses: [ClassInfo] { classes.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) } }

    func load() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        isRunning = true
        defer { isRunning = false }
        apply(await session.snapshot())
        if let path = preferences.string(forKey: Self.lastImageKey) {
            do { try await restoreImage(from: URL(fileURLWithPath: path)) }
            catch { self.error = "Das letzte Image konnte nicht geladen werden: \(error.localizedDescription)" }
        }
    }

    func apply(_ evaluation: EvaluationResult) {
        classes = evaluation.classes
        bindings = evaluation.bindings
        error = evaluation.error
        if let value = evaluation.value { result = value }
        transcript += evaluation.transcript
        // Keep a useful recent history even across many executions.
        if transcript.count > 100_000 { transcript = String(transcript.suffix(80_000)) }
    }

    func run(printResult: Bool = false) async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        let source: String
        let text = workspace as NSString
        if workspaceSelection.length > 0, NSMaxRange(workspaceSelection) <= text.length {
            source = text.substring(with: workspaceSelection)
        } else { source = workspace }
        let evaluation = await session.evaluate(source)
        apply(evaluation)
        // An evaluation may change reachable objects even when it ends in an error.
        imageHasChanges = true
        if printResult, let value = evaluation.value { transcript += "→ \(value)\n" }
    }

    func acceptMethod() async {
        guard !isRunning, let selectedClass, !isPrimitive else { return }
        isRunning = true
        defer { isRunning = false }
        let evaluation = await session.compile(methodSource, in: selectedClass)
        apply(evaluation)
        if evaluation.error == nil {
            imageHasChanges = true
            selectedMethod = currentClass?.methods.first { $0.source == methodSource }?.selector
        }
    }

    func chooseClass() {
        selectedMethod = nil
        methodSource = ""
        methodSelection = NSRange(location: 0, length: 0)
        mode = .browser
    }

    func chooseMethod() {
        methodSource = currentMethod?.source ?? ""
        methodSelection = NSRange(location: 0, length: 0)
        mode = .browser
    }

    func newMethod() {
        selectedMethod = nil
        methodSource = "newMethod\n    ^ self"
        methodSelection = NSRange(location: 0, length: 0)
        mode = .browser
    }

    func createClass(name: String, fields: String) async -> Bool {
        guard !isRunning else { return false }
        isRunning = true
        defer { isRunning = false }
        let escapedName = name.replacingOccurrences(of: "'", with: "''")
        let escapedFields = fields.replacingOccurrences(of: "'", with: "''")
        let evaluation = await session.evaluate("Object subclass: #'\(escapedName)' instanceVariableNames: '\(escapedFields)'")
        apply(evaluation)
        if evaluation.error == nil {
            imageHasChanges = true
            selectedClass = name
            newMethod()
            return true
        }
        return false
    }

    func reset() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        apply(await session.reset())
        selectedClass = "Counter"
        selectedMethod = nil
        methodSource = ""
        result = "Neue Sitzung. Counter und die Basisklassen sind bereit."
        transcript = ""
        imageURL = nil
        imageHasChanges = true
        preferences.removeObject(forKey: Self.lastImageKey)
    }

    func example(_ text: String) {
        workspace = text
        workspaceSelection = NSRange(location: 0, length: 0)
        workspaceURL = nil
        mode = .workspace
    }

    func openWorkspace() {
        guard !isRunning else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, UTType(filenameExtension: "st") ?? .plainText]
        panel.allowsOtherFileTypes = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            example(try String(contentsOf: url, encoding: .utf8))
            workspaceURL = url
        } catch { self.error = error.localizedDescription }
    }

    func saveWorkspace() {
        guard !isRunning else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "st") ?? .plainText]
        panel.nameFieldStringValue = workspaceURL?.lastPathComponent ?? "Workspace.st"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try workspace.write(to: url, atomically: true, encoding: .utf8)
            workspaceURL = url
            result = "Workspace gespeichert: \(url.lastPathComponent)"
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    func openImage() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        let panel = NSOpenPanel()
        panel.title = "Smalltalk-Image öffnen"
        panel.allowedContentTypes = [Self.imageType]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try await restoreImage(from: url) }
        catch { self.error = "Image konnte nicht geladen werden: \(error.localizedDescription)" }
    }

    func saveImage(asNewFile: Bool = false) async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        let url: URL
        if let imageURL, !asNewFile { url = imageURL }
        else {
            let panel = NSSavePanel()
            panel.title = "Smalltalk-Image speichern"
            panel.allowedContentTypes = [Self.imageType]
            panel.nameFieldStringValue = imageURL?.lastPathComponent ?? "Smalltalk.stimage"
            panel.directoryURL = imageURL?.deletingLastPathComponent()
            guard panel.runModal() == .OK, let selectedURL = panel.url else { return }
            url = selectedURL
        }
        let savedWorkspace = workspace
        let savedTranscript = transcript
        do {
            try await session.saveImage(to: url, workspace: savedWorkspace, transcript: savedTranscript)
            imageURL = url
            preferences.set(url.path, forKey: Self.lastImageKey)
            imageHasChanges = workspace != savedWorkspace || transcript != savedTranscript
            result = "Image gespeichert: \(url.lastPathComponent)"
            error = nil
        } catch { self.error = "Image konnte nicht gespeichert werden: \(error.localizedDescription)" }
    }

    private func restoreImage(from url: URL) async throws {
        // The session swaps its runtime only after the complete image is valid.
        let image = try await session.loadImage(from: url)
        apply(image.evaluation)
        workspace = image.workspace
        transcript = image.transcript
        workspaceURL = nil
        workspaceSelection = NSRange(location: 0, length: 0)
        if !classes.contains(where: { $0.name == selectedClass }) { selectedClass = classes.first?.name }
        selectedMethod = nil
        methodSource = ""
        methodSelection = NSRange(location: 0, length: 0)
        mode = .workspace
        search = ""
        imageURL = url
        imageHasChanges = false
        preferences.set(url.path, forKey: Self.lastImageKey)
        result = "Image geladen: \(url.lastPathComponent)"
        error = nil
    }
}
