import AppKit
import Combine
import SwiftUI

final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Owns the single non-activating overlay panel that hosts the toast stack.
final class OverlayController {
    static let shared = OverlayController()
    private let store = Store.shared
    private var panel: OverlayPanel!
    private var hosting: NSHostingView<ToastStackView>!
    private var keyMonitor: Any?
    private var bag = Set<AnyCancellable>()
    static let panelWidth: CGFloat = 472   // 440 panel + 16 pt shadow margin each side

    private init() {
        panel = OverlayPanel(contentRect: NSRect(x: 0, y: 0, width: Self.panelWidth, height: 200),
                             styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.acceptsMouseMovedEvents = true
        panel.isMovableByWindowBackground = false
        panel.appearance = NSAppearance(named: .darkAqua)
        hosting = NSHostingView(rootView: ToastStackView(store: store))
        hosting.sizingOptions = [.intrinsicContentSize]
        panel.contentView = hosting

        store.onItemsChanged = { [weak self] in self?.relayout() }
        store.objectWillChange.sink { [weak self] _ in DispatchQueue.main.async { self?.relayout() } }.store(in: &bag)

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, self.panel.isKeyWindow else { return e }
            return self.handleKey(e) ? nil : e
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
            guard let self else { return }
            if self.store.focused { self.store.focused = false }
        }
        Hotkey.shared.onPress = { [weak self] in self?.toggleFocus() }
        Hotkey.shared.registerFromPrefs()
    }

    // MARK: layout

    func relayout() {
        guard !store.items.isEmpty else { panel.orderOut(nil); return }
        hosting.invalidateIntrinsicContentSize(); hosting.layoutSubtreeIfNeeded()
        var h = hosting.intrinsicContentSize.height
        if !(h > 0) || h == NSView.noIntrinsicMetric { h = hosting.fittingSize.height }
        let height = max(80, min(h, screen.visibleFrame.height - 24))
        let sf = screen.visibleFrame
        let origin = NSPoint(x: sf.maxX - Self.panelWidth - 4, y: sf.maxY - height - 6)
        panel.setFrame(NSRect(origin: origin, size: NSSize(width: Self.panelWidth, height: height)), display: true)
        if !panel.isVisible { panel.orderFrontRegardless() }
        snapshotIfRequested()
    }

    /// Dev aid: BECKON_SNAPSHOT_DIR=/some/dir makes every relayout write a PNG of the overlay window.
    private func snapshotIfRequested() {
        guard let dir = ProcessInfo.processInfo.environment["BECKON_SNAPSHOT_DIR"] else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [self] in
            let stamp = Int(Date().timeIntervalSince1970 * 1000) % 10_000_000
            let url = URL(fileURLWithPath: dir).appendingPathComponent("overlay-\(stamp).png")
            if let cg = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(panel.windowNumber), [.boundsIgnoreFraming, .bestResolution]), cg.width > 1 {
                let rep = NSBitmapImageRep(cgImage: cg)
                try? rep.representation(using: .png, properties: [:])?.write(to: url); return
            }
            let renderer = ImageRenderer(content: ToastStackView(store: store).frame(width: Self.panelWidth).background(Color.gray))
            renderer.scale = 2
            if let cg = renderer.cgImage { try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?.write(to: url) }
        }
    }

    private var screen: NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    // MARK: focus

    func toggleFocus() { store.focused ? unfocus() : focus() }

    func focus() {
        guard !store.items.isEmpty else { return }
        store.focused = true
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        relayout()
    }

    func unfocus() {
        store.focused = false
        if panel.isKeyWindow { panel.resignKey() }
        if let prev = store.previousApp, prev.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            prev.activate(options: [])
        } else {
            NSApp.hide(nil)
        }
        relayout()
    }

    // MARK: keys (only while the panel is key)

    private func handleKey(_ e: NSEvent) -> Bool {
        guard let top = store.items.first else { return false }
        let flags = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isTyping = panel.firstResponder is NSTextView
        if e.keyCode == 53 { unfocus(); return true }                         // Esc
        if flags.contains(.option), e.charactersIgnoringModifiers?.lowercased() == "j" { store.jump(to: top); return true }   // ⌥J take me to Claude
        if flags.contains(.option), let n = Int(e.charactersIgnoringModifiers ?? ""), (1...9).contains(n) {
            return numberAction(top, n)
        }
        // Plain digits are shortcuts only when there is no text field to type into.
        var hasReplyField = false
        if case .finished = top.kind, top.session.canReceiveMessages, !top.sent { hasReplyField = true }
        if !isTyping, !hasReplyField, flags.isEmpty, let n = Int(e.charactersIgnoringModifiers ?? ""), (1...9).contains(n) {
            return numberAction(top, n)
        }
        if e.keyCode == 36 || e.keyCode == 76 {                                 // Return / Enter
            switch top.kind {
            case .permission: store.allow(top, always: false); return true
            case .question(let qs, _):
                if qs.indices.contains(top.currentQuestion), qs[top.currentQuestion].multiSelect, !(top.answers[top.currentQuestion] ?? []).isEmpty { store.advanceQuestion(top); return true }
                return false
            case .finished: if isTyping { return false }; if top.session.canReceiveMessages { store.sendReply(top) } else { store.jump(to: top) }; return true
            case .info: store.dismiss(top); return true
            }
        }
        return false
    }

    private func numberAction(_ top: PendingItem, _ n: Int) -> Bool {
        switch top.kind {
        case .permission:
            if n == 1 { store.allow(top, always: false) } else if n == 2 { store.allow(top, always: true) } else if n == 3 { store.deny(top) } else { return false }
            return true
        case .question(let qs, _):
            guard qs.indices.contains(top.currentQuestion), qs[top.currentQuestion].options.indices.contains(n - 1) else { return false }
            store.choose(top, option: n - 1); return true
        case .finished:
            if top.session.canReceiveMessages { if n == 1 { store.dismiss(top); return true }; return false }
            if n == 1 { store.jump(to: top); return true }
            if n == 2 { store.dismiss(top); return true }
            return false
        case .info:
            if n == 1 { store.jump(to: top); return true }
            if n == 2 { store.dismiss(top); return true }
            return false
        }
    }
}
