import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBar: StatusBarController!
    let server = SocketServer()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Brand.registerFonts()
        _ = OverlayController.shared
        statusBar = StatusBarController()
        try? Installer.installShim()              // keep ~/.beckon/bin/beckon-hook in sync with this build
        server.onEnvelope = { env, conn in Store.shared.handle(env, conn) }
        do { try server.start() } catch { Onboarding.error(error) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { Onboarding.promptInstall() }
        if ProcessInfo.processInfo.environment["BECKON_SNAPSHOT_FOCUSED"] != nil { Store.shared.focused = true }   // dev aid for snapshots
        ClaudeCLI.version { v in if let v { Log.event(["kind": "claude-version", "version": v]) } }
        UpdateChecker.shared.onChange = { [weak self] in self?.statusBar.refreshIconPublic() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { UpdateChecker.shared.checkIfDue() }
        Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { _ in UpdateChecker.shared.checkIfDue() }
        signal(SIGTERM) { _ in DispatchQueue.main.async { NSApp.terminate(nil) } }
    }

    func applicationWillTerminate(_ notification: Notification) {
        for it in Store.shared.items { it.connection?.passthrough() }   // never leave Claude hanging
        server.stop()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
