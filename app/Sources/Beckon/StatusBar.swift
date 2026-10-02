import AppKit
import Combine
import ServiceManagement

final class StatusBarController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let store = Store.shared
    private var bag = Set<AnyCancellable>()

    override init() {
        super.init()
        let menu = NSMenu(); menu.delegate = self; item.menu = menu
        store.objectWillChange.sink { [weak self] _ in DispatchQueue.main.async { self?.refreshIcon() } }.store(in: &bag)
        refreshIcon()
    }

    func refreshIconPublic() { refreshIcon() }
    private func refreshIcon() {
        guard let b = item.button else { return }
        let n = store.pendingCount
        if n == 0, !Prefs.paused, let url = Bundle.main.url(forResource: "menubar", withExtension: "png"), let img = NSImage(contentsOf: url) {
            img.isTemplate = true; img.size = NSSize(width: 18, height: 18); b.image = img
        } else {
            let symbol = Prefs.paused ? "bell.slash" : "bell.badge.fill"
            b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Beckon")
            b.image?.isTemplate = true
        }
        b.title = n > 0 ? " \(n)" : ""
        b.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        // Pending
        if store.items.isEmpty {
            menu.addItem(withTitle: "Nothing waiting on you", action: nil, keyEquivalent: "")
        } else {
            for it in store.items.prefix(8) {
                let mi = NSMenuItem(title: "\(it.session.projectName) — \(it.oneLine.prefix(60))", action: #selector(focusOverlay), keyEquivalent: "")
                mi.target = self; mi.image = dot(it.session.color); menu.addItem(mi)
            }
            let f = NSMenuItem(title: "Focus overlay", action: #selector(focusOverlay), keyEquivalent: " ")
            f.keyEquivalentModifierMask = [.option]; f.target = self; menu.addItem(f)
        }
        menu.addItem(.separator())
        // Sessions
        let live = store.sessions.values.filter { $0.id != "__test" }.sorted { $0.lastSeen > $1.lastSeen }
        let head = NSMenuItem(title: live.isEmpty ? "No Claude Code sessions seen yet" : "Sessions", action: nil, keyEquivalent: ""); head.isEnabled = false; menu.addItem(head)
        for s in live.prefix(10) {
            let mi = NSMenuItem(title: "\(s.projectName)  ·  \(s.host.name)\(s.isSubagentActive ? "  ·  subagent running" : "")", action: #selector(jumpSession(_:)), keyEquivalent: "")
            mi.representedObject = s.id; mi.target = self; mi.image = dot(s.color); menu.addItem(mi)
        }
        menu.addItem(.separator())
        // Install state
        switch Installer.status() {
        case .installed:
            let mi = NSMenuItem(title: "Hooks installed ✓", action: nil, keyEquivalent: ""); mi.isEnabled = false; menu.addItem(mi)
            menu.addItem(withTitle: "Remove hooks from ~/.claude/settings.json…", action: #selector(uninstallHooks), keyEquivalent: "").target = self
        case .partial(let missing):
            menu.addItem(withTitle: "Hooks partially installed (missing \(missing.count)) — Repair…", action: #selector(installHooks), keyEquivalent: "").target = self
        case .notInstalled, .noShim:
            menu.addItem(withTitle: "Install hooks into ~/.claude/settings.json…", action: #selector(installHooks), keyEquivalent: "").target = self
        }
        menu.addItem(withTitle: "Send test alert", action: #selector(testAlert), keyEquivalent: "t").target = self
        if let note = ClaudeCLI.compatibilityNote() { let mi = NSMenuItem(title: "⚠︎ " + note.prefix(70) + "…", action: nil, keyEquivalent: ""); mi.isEnabled = false; mi.toolTip = note; menu.addItem(mi) }
        menu.addItem(.separator())
        let pause = NSMenuItem(title: "Paused (pass everything to the terminal)", action: #selector(togglePause), keyEquivalent: ""); pause.state = Prefs.paused ? .on : .off; pause.target = self; menu.addItem(pause)
        if let rel = UpdateChecker.shared.available {
            menu.addItem(withTitle: "Update available: Beckon \(rel.version) — Download…", action: #selector(downloadUpdate), keyEquivalent: "").target = self
        } else {
            menu.addItem(withTitle: "Check for Updates…", action: #selector(checkUpdates), keyEquivalent: "").target = self
        }
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Open log", action: #selector(openLog), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Quit Beckon", action: #selector(quit), keyEquivalent: "q").target = self
    }

    private func dot(_ c: NSColor) -> NSImage {
        let img = NSImage(size: NSSize(width: 10, height: 10), flipped: false) { r in c.setFill(); NSBezierPath(ovalIn: r.insetBy(dx: 1, dy: 1)).fill(); return true }
        return img
    }

    @objc private func focusOverlay() { OverlayController.shared.focus() }
    @objc private func jumpSession(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let s = store.sessions[id] else { return }
        if let pid = s.hostPid, let app = NSRunningApplication(processIdentifier: pid) { app.activate(options: [.activateIgnoringOtherApps]) }
    }
    @objc func installHooks() { Onboarding.promptInstall(force: true) }
    @objc private func uninstallHooks() {
        let a = NSAlert(); a.messageText = "Remove Beckon's hooks?"; a.informativeText = "Only the entries that point at beckon-hook are removed. Your other hooks stay untouched. A backup of settings.json is in ~/.beckon/backups."
        a.addButton(withTitle: "Remove"); a.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if a.runModal() == .alertFirstButtonReturn { do { try Installer.uninstall() } catch { Onboarding.error(error) } }
    }
    @objc private func testAlert() { store.pushTestCard() }
    @objc private func togglePause() { Prefs.paused.toggle(); refreshIcon() }
    @objc private func openSettings() { SettingsWindow.show() }
    @objc private func checkUpdates() { UpdateChecker.shared.check(manual: true) }
    @objc private func downloadUpdate() { if let r = UpdateChecker.shared.available { NSWorkspace.shared.open(r.url) } }
    @objc private func toggleLogin() {
        do { if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() } } catch { Onboarding.error(error) }
    }
    @objc private func openLog() { NSWorkspace.shared.open(Paths.log) }
    @objc private func quit() { NSApp.terminate(nil) }
}

enum Onboarding {
    private static var window: NSWindow?

    static func promptInstall(force: Bool = false) {
        if !force, Prefs.didOnboard, case .installed = Installer.status() { return }
        if let w = window { w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let view = OnboardingView(onInstall: {
            do { try Installer.install(); Prefs.didOnboard = true; closeWindow(); Store.shared.pushTestCard() } catch let e { error(e) }
        }, onLater: { Prefs.didOnboard = true; closeWindow() })
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 10), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        w.title = "Beckon"; w.titlebarAppearsTransparent = true; w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: view)
        w.setContentSize(w.contentView!.fittingSize)
        w.center(); w.level = .floating
        window = w
        NSApp.activate(ignoringOtherApps: true); w.makeKeyAndOrderFront(nil)
    }
    private static func closeWindow() { window?.orderOut(nil); window = nil }
    static func error(_ e: Error) {
        let a = NSAlert(error: e); NSApp.activate(ignoringOtherApps: true); a.runModal()
    }
}

import SwiftUI
struct OnboardingView: View {
    let onInstall: () -> Void
    let onLater: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "bell.badge.fill").font(.system(size: 28)).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connect Beckon to Claude Code").font(.system(size: 17, weight: .semibold))
                    Text("One click. Reversible. No restart needed.").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            Text("Beckon adds hook entries to ~/.claude/settings.json so Claude Code tells it when a session needs you — in any terminal, the VS Code / JetBrains extension, or Claude Desktop. Your existing hooks are kept exactly as they are and a backup is saved to ~/.beckon/backups.")
                .font(.system(size: 12.5)).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Installer.hooks, id: \.0) { h in
                    HStack(spacing: 6) {
                        Text(h.0).font(.system(size: 11.5, weight: .medium, design: .monospaced))
                        if let m = h.1, !m.isEmpty { Text("matcher \(m)").font(.system(size: 11)).foregroundStyle(.secondary) }
                        Spacer()
                        Text("timeout \(h.2)s").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(10).background(Color.primary.opacity(0.05)).clipShape(RoundedRectangle(cornerRadius: 8))
            Text("If Beckon is not running, the hook exits in about a millisecond and Claude Code behaves exactly as before. Beckon only steps in while the terminal that asked is not the app in front of you.")
                .font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("Note: in Claude Code's auto permission mode Claude rarely asks for permission, so you will mostly see questions and \"finished\" cards. Start a session with `claude --permission-mode manual` to get permission cards.")
                .font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if ClaudeCLI.locate() == nil {
                Text("Claude Code was not found in the usual places (~/.local/bin, Homebrew). Beckon still works if it is installed elsewhere; the hooks run from inside Claude Code.").font(.system(size: 11.5)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Text("Hotkey: ⌥Space focuses the overlay · Esc returns to your app").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button("Later", action: onLater).keyboardShortcut(.cancelAction)
                Button("Install hooks", action: onInstall).keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }
        .padding(22).frame(width: 520)
    }
}
