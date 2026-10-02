import AppKit
import Combine
import Foundation

/// Central state: sessions, pending items, decisions. Main-thread only.
final class Store: ObservableObject {
    static let shared = Store()

    @Published private(set) var sessions: [String: Session] = [:]
    @Published private(set) var items: [PendingItem] = []       // newest first
    @Published var focused = false                               // overlay has keyboard focus
    @Published var hoveredItem: UUID?

    var onItemsChanged: (() -> Void)?
    private var timers: [UUID: Timer] = [:]
    private var lastOtherApp: NSRunningApplication?

    private init() {
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let self, let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            if app.processIdentifier != ProcessInfo.processInfo.processIdentifier { self.lastOtherApp = app }
            self.userArrived(at: app)
        }
        lastOtherApp = NSWorkspace.shared.frontmostApplication
    }

    var pendingCount: Int { items.count }
    var blockingCount: Int { items.filter { $0.kind.isBlocking }.count }
    var previousApp: NSRunningApplication? { lastOtherApp }

    // MARK: - Ingest

    func handle(_ env: HookEnvelope, _ conn: HookConnection) {
        let session = upsertSession(env)
        let event = env.eventName
        Log.event(["kind": "hook", "event": event, "session": session.id, "project": session.projectName, "host": session.host.name])

        switch event {
        case "PermissionRequest":
            guard let tool = env.payload["tool_name"] as? String else { conn.passthrough(); return }
            let input = env.payload["tool_input"] as? [String: Any] ?? [:]
            let suggestions = env.payload["permission_suggestions"] as? [[String: Any]] ?? []
            enqueue(PendingItem(session: session, kind: .permission(tool: tool, input: input, suggestions: suggestions),
                                connection: conn, deadline: Date().addingTimeInterval(540)))

        case "PreToolUse":
            guard env.payload["tool_name"] as? String == "AskUserQuestion" else { conn.passthrough(); return }
            let input = env.payload["tool_input"] as? [String: Any] ?? [:]
            let qs = Question.parse(input["questions"])
            guard !qs.isEmpty else { conn.passthrough(); return }
            enqueue(PendingItem(session: session, kind: .question(questions: qs, originalInput: input), connection: conn, deadline: Date().addingTimeInterval(540)))

        case "Stop":
            // Never hold Claude's turn. The follow-up goes through the session's messaging socket instead.
            conn.passthrough()
            if env.payload["stop_hook_active"] as? Bool == true { return }
            if let bg = env.payload["background_tasks"] as? [[String: Any]], !bg.isEmpty { return }
            var summary = (env.payload["last_assistant_message"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if summary.isEmpty { summary = Transcript.lastAssistantText(path: session.transcriptPath) }
            summary = summary.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .replacingOccurrences(of: "[#*`_>]+", with: "", options: .regularExpression)
            if summary.count > 220 { summary = String(summary.prefix(220)) + "…" }
            // One "Finished" card per session: a newer turn replaces the older card.
            items.removeAll { if case .finished = $0.kind, $0.session.id == session.id { return true }; return false }
            enqueue(PendingItem(session: session, kind: .finished(summary: summary), connection: nil, deadline: nil))

        case "Notification":
            conn.passthrough()
            let type = env.payload["notification_type"] as? String ?? ""
            let msg = (env.payload["message"] as? String) ?? ""
            // If this session already has a card (permission, question or finished), a "waiting" notice adds nothing.
            if items.contains(where: { $0.session.id == session.id }) { return }
            switch type {
            case "permission_prompt": enqueue(PendingItem(session: session, kind: .info(text: msg.isEmpty ? "Claude is waiting for permission in \(session.host.name)." : msg), connection: nil, deadline: nil))
            case "idle_prompt": enqueue(PendingItem(session: session, kind: .info(text: msg.isEmpty ? "Claude is waiting for your input." : msg), connection: nil, deadline: nil))
            case "elicitation_dialog", "elicitation_url_dialog": enqueue(PendingItem(session: session, kind: .info(text: msg.isEmpty ? "An MCP server needs your input in \(session.host.name)." : msg), connection: nil, deadline: nil))
            case "agent_needs_input": enqueue(PendingItem(session: session, kind: .info(text: msg.isEmpty ? "A background agent needs your input." : msg), connection: nil, deadline: nil))
            default: break
            }

        case "UserPromptSubmit":
            conn.passthrough()
            // The user is typing in this session → anything we hold for it is stale.
            resolveAll(for: session.id, passthrough: true)

        case "SubagentStart": conn.passthrough(); session.isSubagentActive = true
        case "SubagentStop": conn.passthrough(); session.isSubagentActive = false
        case "SessionStart": conn.passthrough()
        case "SessionEnd":
            conn.passthrough()
            resolveAll(for: session.id, passthrough: true)
            sessions.removeValue(forKey: session.id)
        default: conn.passthrough()
        }
    }

    @discardableResult
    private func upsertSession(_ env: HookEnvelope) -> Session {
        let app = ProcessTree.owningApp(from: env.ppid)
        let host = Host.detect(env: env.env, bundleIdFromProcess: app?.bundleIdentifier)
        let s: Session
        if let existing = sessions[env.sessionId] {
            s = existing; s.cwd = env.cwd; s.env = env.env
            if s.hostPid == nil { s.hostPid = app?.processIdentifier }
            if s.host == .unknown { s.host = host }
        } else {
            s = Session(id: env.sessionId, cwd: env.cwd, host: host, hostPid: app?.processIdentifier, env: env.env)
            sessions[s.id] = s
        }
        if let t = env.payload["transcript_path"] as? String { s.transcriptPath = t }
        s.lastSeen = Date()
        return s
    }

    // MARK: - Queue

    private func enqueue(_ item: PendingItem) {
        if Prefs.paused { item.connection?.passthrough(); return }
        // "Only when you're away": if the owning app is frontmost, let Claude's own prompt handle it.
        if !Prefs.showWhenHostInFront, let front = NSWorkspace.shared.frontmostApplication, let hp = item.session.hostPid,
           front.processIdentifier == hp {
            Log.event(["kind": "silenced-host-in-front", "session": item.session.id, "host": item.session.host.name])
            item.connection?.passthrough(); return
        }
        // Collapse duplicate informational items per session.
        if case .info = item.kind { items.removeAll { if case .info = $0.kind, $0.session.id == item.session.id { return true }; return false } }
        items.insert(item, at: 0)
        item.connection?.onPeerClosed = { [weak self, weak item] in
            guard let self, let item, self.items.contains(where: { $0.id == item.id }) else { return }
            Log.event(["kind": "peer-closed", "session": item.session.id])
            self.remove(item)
        }
        if let deadline = item.deadline {
            let t = Timer(fire: deadline, interval: 0, repeats: false) { [weak self, weak item] _ in
                guard let self, let item else { return }
                self.expire(item)
            }
            RunLoop.main.add(t, forMode: .common); timers[item.id] = t
        }
        if Prefs.soundEnabled { if case .info = item.kind {} else { NSSound(named: "Tink")?.play() } }
        onItemsChanged?()
    }

    private func expire(_ item: PendingItem) {
        timers[item.id]?.invalidate(); timers[item.id] = nil
        item.connection?.passthrough(); remove(item)       // safety net below Claude's own hook timeout
    }

    private func remove(_ item: PendingItem) {
        timers[item.id]?.invalidate(); timers[item.id] = nil
        items.removeAll { $0.id == item.id }
        if items.isEmpty, focused { OverlayController.shared.unfocus() }
        onItemsChanged?()
    }

    /// The user switched to the app that owns this session → hand everything back to Claude's native prompt.
    private func userArrived(at app: NSRunningApplication) {
        guard !Prefs.showWhenHostInFront else { return }
        let pid = app.processIdentifier
        for item in items where item.session.hostPid == pid { item.connection?.passthrough(); remove(item) }
    }

    private func resolveAll(for sessionId: String, passthrough: Bool) {
        for item in items where item.session.id == sessionId { if passthrough { item.connection?.passthrough() }; remove(item) }
    }

    // MARK: - Decisions

    func allow(_ item: PendingItem, always: Bool) {
        guard case .permission(let tool, let input, let suggestions) = item.kind else { return }
        var decision: [String: Any] = ["behavior": "allow"]
        var written: [String] = []
        if always {
            let rules = PermissionSummary.alwaysRules(tool: tool, input: input, suggestions: suggestions, cwd: item.session.cwd)
            decision["updatedPermissions"] = rules
            written = rules.flatMap { ($0["rules"] as? [[String: Any]]) ?? [] }.map(PermissionSummary.describe)
        }
        item.connection?.reply(["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": decision]])
        var entry: [String: Any] = ["kind": "decision", "session": item.session.id, "tool": tool, "chip": PermissionSummary.chip(tool: tool, input: input), "decision": always ? "allow-always" : "allow", "cwd": item.session.cwd]
        if always { entry["rules"] = written }
        Log.event(entry)
        remove(item)
    }

    func deny(_ item: PendingItem) {
        guard case .permission(let tool, let input, _) = item.kind else { return }
        item.connection?.reply(["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": ["behavior": "deny", "message": "Denied by the user from Beckon."]]])
        Log.event(["kind": "decision", "session": item.session.id, "tool": tool, "chip": PermissionSummary.chip(tool: tool, input: input), "decision": "deny"])
        remove(item)
    }

    /// Select an option for the current question; single-select advances/sends automatically.
    func choose(_ item: PendingItem, option: Int) {
        guard case .question(let qs, _) = item.kind, qs.indices.contains(item.currentQuestion) else { return }
        let q = qs[item.currentQuestion]
        var set = item.answers[item.currentQuestion] ?? []
        if q.multiSelect { if set.contains(option) { set.remove(option) } else { set.insert(option) } } else { set = [option] }
        item.answers[item.currentQuestion] = set
        if !q.multiSelect { advanceQuestion(item) }
    }

    func advanceQuestion(_ item: PendingItem) {
        guard case .question(let qs, let original) = item.kind else { return }
        if item.currentQuestion + 1 < qs.count { item.currentQuestion += 1; onItemsChanged?(); return }
        // All answered → reply. Shape: answers keyed by question text, labels comma-joined for multi-select.
        var answers: [String: Any] = [:]
        for (i, q) in qs.enumerated() {
            let labels = (item.answers[i] ?? []).sorted().compactMap { q.options.indices.contains($0) ? q.options[$0].label : nil }
            answers[q.text] = q.multiSelect ? labels : (labels.first ?? "")
        }
        var updated = original; updated["answers"] = answers
        item.connection?.reply(["hookSpecificOutput": ["hookEventName": "PreToolUse", "permissionDecision": "allow", "updatedInput": updated]])
        Log.event(["kind": "answer", "session": item.session.id, "answers": answers])
        remove(item)
    }

    func sendReply(_ item: PendingItem) {
        guard case .finished = item.kind, !item.sent else { return }
        let text = item.replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        item.sendError = nil
        MessagingClient.send(text, to: item.session) { [weak self, weak item] result in
            guard let self, let item else { return }
            switch result {
            case .success:
                Log.event(["kind": "reply", "transport": "messaging-socket", "session": item.session.id, "text": text])
                item.sent = true; self.onItemsChanged?()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [weak self, weak item] in if let item { self?.remove(item) } }
            case .failure(let f):
                Log.event(["kind": "reply-failed", "session": item.session.id, "error": f.localizedDescription])
                item.sendError = f.localizedDescription; self.onItemsChanged?()
            }
        }
    }

    /// Dismiss: for blocking items this is a passthrough (Claude shows its own prompt / stops normally).
    func dismiss(_ item: PendingItem) {
        item.connection?.passthrough()
        remove(item)
    }

    /// "Take me to Claude": bring the owning terminal/IDE forward and hand every pending item of that
    /// session back to Claude's native prompt, so the user arrives at a terminal that is ready for them.
    func jump(to item: PendingItem) {
        let sid = item.session.id
        for it in items where it.session.id == sid { it.connection?.passthrough(); remove(it) }
        Log.event(["kind": "jump", "session": sid, "host": item.session.host.name])
        if focused { OverlayController.shared.unfocus() }
        if let pid = item.session.hostPid, let app = NSRunningApplication(processIdentifier: pid) { app.activate(options: [.activateIgnoringOtherApps]) }
        else if let bid = item.session.host.bundleId, let app = NSRunningApplication.runningApplications(withBundleIdentifier: bid).first { app.activate(options: [.activateIgnoringOtherApps]) }
    }

    /// Synthetic card used by onboarding and the "Test alert" menu item.
    func pushTestCard() {
        let s = sessions["__test"] ?? Session(id: "__test", cwd: NSHomeDirectory() + "/Developer/your-project", host: Host(name: "Beckon", bundleId: nil, glyph: "bell"), hostPid: nil, env: [:])
        sessions["__test"] = s
        enqueue(PendingItem(session: s, kind: .permission(tool: "Bash", input: ["command": "npm test -- --coverage"], suggestions: []), connection: nil, deadline: nil))
    }
}
