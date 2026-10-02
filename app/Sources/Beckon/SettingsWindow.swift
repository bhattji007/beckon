import AppKit
import Carbon
import ServiceManagement
import SwiftUI

enum SettingsWindow {
    private static var window: NSWindow?
    static func show() {
        if let w = window { w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 10), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "Beckon Settings"; w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: SettingsView())
        w.setContentSize(w.contentView!.fittingSize); w.center()
        window = w; NSApp.activate(ignoringOtherApps: true); w.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @State private var sound = Prefs.soundEnabled
    @State private var showFront = Prefs.showWhenHostInFront
    @State private var paused = Prefs.paused
    @State private var updates = Prefs.checkUpdates
    @State private var login = SMAppService.mainApp.status == .enabled
    @State private var hotkey = Hotkey.describe(keyCode: Prefs.hotkeyKeyCode, modifiers: Prefs.hotkeyModifiers)
    @State private var recording = false
    @State private var monitor: Any?
    @State private var claudeVersion = ClaudeCLI.cachedVersion ?? "…"

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            section("Behaviour") {
                Toggle("Only show cards when the asking terminal is not in front", isOn: Binding(get: { !showFront }, set: { showFront = !$0; Prefs.showWhenHostInFront = showFront }))
                Text("Recommended. When you are already looking at that terminal, Claude's own prompt is enough. Switching to the terminal while a card is up hands it back instantly.").font(.system(size: 11)).foregroundStyle(.secondary)
                Toggle("Play a sound for new cards", isOn: $sound).onChange(of: sound) { _, v in Prefs.soundEnabled = v }
                Toggle("Paused — pass everything to the terminal", isOn: $paused).onChange(of: paused) { _, v in Prefs.paused = v }
            }
            section("Keyboard") {
                HStack {
                    Text("Focus the overlay")
                    Spacer()
                    Button(recording ? "Press keys… (Esc cancels)" : hotkey) { recording ? stopRecording() : startRecording() }
                        .buttonStyle(.bordered).frame(minWidth: 160)
                }
                Text("Then ⌥1 ⌥2 ⌥3 act on the top card, ⏎ is the primary action, ⌥J takes you to Claude, Esc returns to your app.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            section("System") {
                Toggle("Launch Beckon at login", isOn: $login).onChange(of: login) { _, v in
                    do { if v { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } } catch { login = !v }
                }
                Toggle("Check for updates daily", isOn: $updates).onChange(of: updates) { _, v in Prefs.checkUpdates = v }
                HStack { Text("Claude Code"); Spacer(); Text(claudeVersion).foregroundStyle(.secondary) }
                if let note = ClaudeCLI.compatibilityNote() { Text(note).font(.system(size: 11)).foregroundStyle(.orange) }
            }
            section("Maintenance") {
                HStack(spacing: 10) {
                    Button("Copy diagnostics") { Diagnostics.copyToPasteboard() }
                    Button("Open log") { NSWorkspace.shared.open(Paths.log) }
                    Spacer()
                    Button("Uninstall Beckon…") { Uninstaller.run() }.foregroundStyle(.red)
                }
                Text("Uninstall removes the hook entries, ~/.beckon and the login item, and moves the app to the Trash. Your other Claude Code settings are untouched.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            HStack { Text("Beckon \(AppInfo.version)").font(.system(size: 11)).foregroundStyle(.secondary); Spacer()
                if let page = AppInfo.downloadPage { Link("Website", destination: page).font(.system(size: 11)) } }
        }
        .padding(22).frame(width: 480)
        .onAppear { ClaudeCLI.version { v in claudeVersion = v ?? "not found" } }
        .onDisappear { stopRecording() }
    }

    @ViewBuilder private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            content()
        }
    }

    private func startRecording() {
        recording = true
        Hotkey.shared.unregister()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            if e.keyCode == 53 { stopRecording(); return nil }
            let flags = e.modifierFlags.intersection([.command, .option, .shift, .control])
            let mods = Hotkey.carbonModifiers(from: flags)
            guard mods != 0 else { return nil }                      // require at least one modifier
            Prefs.hotkeyKeyCode = UInt32(e.keyCode); Prefs.hotkeyModifiers = mods
            hotkey = Hotkey.describe(keyCode: Prefs.hotkeyKeyCode, modifiers: mods)
            stopRecording(); return nil
        }
    }
    private func stopRecording() {
        recording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        Hotkey.shared.registerFromPrefs()
    }
}

enum Diagnostics {
    static func text() -> String {
        var lines: [String] = []
        lines.append("Beckon \(AppInfo.version) · macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        lines.append("Claude Code: \(ClaudeCLI.cachedVersion ?? "unknown") at \(ClaudeCLI.locate() ?? "not found")")
        switch Installer.status() {
        case .installed: lines.append("Hooks: installed")
        case .partial(let m): lines.append("Hooks: partial, missing \(m.joined(separator: ", "))")
        case .notInstalled: lines.append("Hooks: not installed")
        case .noShim: lines.append("Hooks: shim missing")
        }
        lines.append("Socket: \(FileManager.default.fileExists(atPath: Paths.socket.path) ? "present" : "missing") at \(Paths.socket.path)")
        lines.append("Prefs: sound=\(Prefs.soundEnabled) showWhenHostInFront=\(Prefs.showWhenHostInFront) paused=\(Prefs.paused) hotkey=\(Hotkey.describe(keyCode: Prefs.hotkeyKeyCode, modifiers: Prefs.hotkeyModifiers))")
        lines.append("Sessions: \(Store.shared.sessions.values.map { "\($0.projectName)@\($0.host.name)" }.joined(separator: ", "))")
        lines.append("Pending: \(Store.shared.items.count)")
        if let log = try? String(contentsOf: Paths.log, encoding: .utf8) {
            let tail = log.split(separator: "\n").suffix(30)
            lines.append("--- last \(tail.count) log lines ---"); lines.append(contentsOf: tail.map(String.init))
        }
        return lines.joined(separator: "\n")
    }
    static func copyToPasteboard() {
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text(), forType: .string)
    }
}

enum Uninstaller {
    static func run() {
        let a = NSAlert(); a.messageText = "Uninstall Beckon?"
        a.informativeText = "This removes Beckon's hook entries from ~/.claude/settings.json (other hooks stay), deletes ~/.beckon (shim, socket, log, backups), removes the login item and moves Beckon.app to the Trash. Claude Code keeps working exactly as before."
        a.addButton(withTitle: "Uninstall"); a.addButton(withTitle: "Cancel"); a.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        guard a.runModal() == .alertFirstButtonReturn else { return }
        for it in Store.shared.items { it.connection?.passthrough() }
        try? Installer.uninstall()
        try? SMAppService.mainApp.unregister()
        try? FileManager.default.removeItem(at: Paths.beckonDir)
        if let url = Bundle.main.bundleURL as URL?, url.path.hasSuffix(".app") { try? FileManager.default.trashItem(at: url, resultingItemURL: nil) }
        NSApp.terminate(nil)
    }
}
