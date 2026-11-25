import AppKit

@MainActor
final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    let controller = AppController()
    private var quitPending = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        // Use the bundled artwork for Dock and About, bypassing stale system icons.
        if let icon = Bundle.main.image(forResource: "AppIcon") {
            NSImage(named: NSImage.applicationIconName)?.setName(nil)
            icon.setName(NSImage.applicationIconName)
            NSApp.applicationIconImage = icon
        }
        Task { await controller.load(); NSApp.activate(ignoringOtherApps: true) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if quitPending { return .terminateLater }
        guard sender.modalWindow == nil else { return .terminateCancel }
        guard controller.isRunning || controller.imageNeedsSaving() else { return .terminateNow }

        quitPending = true
        controller.stopDebugging()
        Task {
            await controller.waitForCurrentOperation()
            let shouldQuit = await controller.confirmQuit()
            quitPending = false
            sender.reply(toApplicationShouldTerminate: shouldQuit)
        }
        return .terminateLater
    }
}
