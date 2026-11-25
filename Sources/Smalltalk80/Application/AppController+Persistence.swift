import AppKit
import SmalltalkCore
import UniformTypeIdentifiers

extension AppController {
    private static var imageType: UTType { UTType(filenameExtension: "stimage", conformingTo: .data) ?? .data }

    func reset() async {
        await runOperation {
            guard await confirmSessionReplacement(.reset) else { return }
            // Join outstanding native input before replacing its interpreter world.
            await attemptToFlushWindowState()
            do {
                let replacement = try await session.reset(startingChangeLogAt: unsavedChangeLogURL())
                installReplacement(replacement)
                setSavedImageURL(nil)
            } catch {
                persistenceError = "Could not reset the session: \(error.localizedDescription)"
                presentErrorWithoutActiveWindow(error.localizedDescription, title: "Could not reset the session")
            }
        }
    }

    func openImage() async {
        await runOperation {
            let panel = NSOpenPanel()
            panel.title = "Open Smalltalk Image"
            panel.allowedContentTypes = [Self.imageType]
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = false
            guard panel.runModal() == .OK, let url = panel.url else { return }
            guard await confirmSessionReplacement(.openImage) else { return }
            await attemptToFlushWindowState()
            do {
                try await restoreImage(from: url)
            } catch {
                let alert = NSAlert()
                alert.messageText = "Could not load the image"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
    }

    enum ImageSaveResult {
        case saved, cancelled, failed(String)
    }

    @discardableResult
    func saveImage(asNewFile: Bool = false) async -> ImageSaveResult {
        await runOperation {
            let result = await saveImageWhileRunning(asNewFile: asNewFile)
            if case .failed(let reason) = result {
                presentErrorWithoutActiveWindow(reason, title: "Could not save the image")
            }
            return result
        } ?? .cancelled
    }

    private func saveImageWhileRunning(asNewFile: Bool = false) async -> ImageSaveResult {
        let url: URL
        if let imageURL, !asNewFile { url = imageURL }
        else {
            let panel = NSSavePanel()
            panel.title = "Save Smalltalk Image"
            panel.allowedContentTypes = [Self.imageType]
            panel.nameFieldStringValue = imageURL?.lastPathComponent ?? "Smalltalk.stimage"
            panel.directoryURL = imageURL?.deletingLastPathComponent()
            guard panel.runModal() == .OK, let chosen = panel.url else { return .cancelled }
            url = chosen
        }
        guard await flushWindowStateRequiringSuccess() else {
            let reason = error ?? windowPresentation.windows.compactMap(\.inputError).first
            return .failed(reason ?? "Some pending window or editor changes could not be applied.")
        }
        do {
            try await session.saveImage(to: url, workspace: windowPresentation.workspace?.info.text ?? "", transcript: "")
            apply(await session.snapshot())
            setSavedImageURL(url, includingPendingEdits: true)
            persistenceError = nil
            error = nil
            return .saved
        } catch {
            self.error = "Could not save the image: \(error.localizedDescription)"
            return .failed(error.localizedDescription)
        }
    }

    private enum SessionReplacement {
        case quit, reset, openImage

        var consequence: String {
            switch self {
            case .quit: "quit"
            case .reset: "reset the session"
            case .openImage: "open another image"
            }
        }
    }

    func confirmQuit() async -> Bool {
        await runOperation { await confirmSessionReplacement(.quit) } ?? false
    }

    /// All callers hold isRunning, including while native save panels are open.
    private func confirmSessionReplacement(_ action: SessionReplacement) async -> Bool {
        guard imageNeedsSaving() else { return true }
        let alert = NSAlert()
        alert.messageText = "Save changes to the Smalltalk image?"
        alert.informativeText = "Your changes since the last save will be lost if you \(action.consequence) without saving."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"
        alert.addButton(withTitle: "Don't Save")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            switch await saveImageWhileRunning() {
            case .saved: return !imageNeedsSaving()
            case .cancelled: return false
            case .failed(let reason):
                let failure = NSAlert()
                failure.messageText = "Could not save the image"
                failure.informativeText = reason
                failure.runModal()
                return false
            }
        case .alertThirdButtonReturn: return true
        default: return false
        }
    }

    func startUnsavedChangeLog() async throws {
        try await session.startChangeLog(at: unsavedChangeLogURL())
    }

    private func unsavedChangeLogURL() throws -> URL {
        let base: URL
        if let suite = ProcessInfo.processInfo.environment["ST80_PREFERENCES_SUITE"] {
            // UI tests run in a different sandbox from the app. An explicit
            // directory lets them exercise actual journal I/O failures.
            base = ProcessInfo.processInfo.environment["ST80_CHANGES_DIRECTORY"].map {
                URL(fileURLWithPath: $0, isDirectory: true)
            } ?? FileManager.default.temporaryDirectory.appendingPathComponent("st80-changes-" + suite)
        } else {
            base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("Smalltalk80/Changes")
        }
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent(UUID().uuidString + ".changes")
    }

    func openChanges() async {
        let shouldShowChanges = await runOperation {
            let panel = NSOpenPanel()
            panel.title = "Open Changes Log for Recovery"
            panel.allowedContentTypes = [UTType(filenameExtension: "changes") ?? .plainText]
            panel.directoryURL = changesPath.map { URL(fileURLWithPath: $0).deletingLastPathComponent() }
            guard panel.runModal() == .OK, let url = panel.url else { return false }
            do {
                apply(try await session.importChanges(from: url))
                return true
            } catch {
                let alert = NSAlert()
                alert.messageText = "Could not import the changes log"
                alert.informativeText = error.localizedDescription
                alert.runModal()
                return false
            }
        }
        if shouldShowChanges == true { await showChanges() }
    }

    private func restoreImage(from url: URL) async throws {
        let image = try await session.loadImage(from: url)
        installReplacement(image.evaluation)
        setSavedImageURL(url)
        error = nil
    }
}
