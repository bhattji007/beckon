import AppKit
import Foundation

// MARK: - Session

final class Session: Identifiable {
    let id: String                 // Claude session_id
    var cwd: String
    var projectName: String { (cwd as NSString).lastPathComponent.isEmpty ? "claude" : (cwd as NSString).lastPathComponent }
    var host: Host
    var hostPid: pid_t?            // pid of the GUI app that owns the terminal / IDE
    var env: [String: String]
    var transcriptPath: String?
    var lastSeen = Date()
    var isSubagentActive = false
    /// Cross-session messaging socket exported by the session (CLAUDE_CODE_MESSAGING_SOCKET) — lets Beckon send a follow-up any time.
    var messagingSocket: String? { env["CLAUDE_CODE_MESSAGING_SOCKET"] }
    var messagingToken: String? { env["CLAUDE_CODE_MESSAGING_TOKEN"] }
    var canReceiveMessages: Bool { messagingSocket.map { FileManager.default.fileExists(atPath: $0) } ?? false }
    var color: NSColor { Palette.color(for: cwd) }

    init(id: String, cwd: String, host: Host, hostPid: pid_t?, env: [String: String]) {
        self.id = id; self.cwd = cwd; self.host = host; self.hostPid = hostPid; self.env = env
    }
}

struct Host: Equatable {
    let name: String        // "Ghostty", "VS Code", "Claude Desktop", …
    let bundleId: String?
    let glyph: String       // SF Symbol name

    static let unknown = Host(name: "Terminal", bundleId: nil, glyph: "terminal")
    /// 1–2 letter code for the small glyph box in the overlay.
    var code: String {
        switch name {
        case "Warp": return "W"; case "Ghostty": return "G"; case "iTerm2": return "iT"; case "Terminal": return "T"; case "kitty": return "K"
        case "WezTerm": return "WT"; case "Hyper": return "H"; case "VS Code": return "VS"; case "Cursor": return "Cu"; case "Windsurf": return "WS"
        case "JetBrains": return "JB"; case "Claude Desktop": return "C"; case "SSH": return "S"; case "tmux": return "tm"; case "Beckon": return "B"
        default: return String(name.prefix(1))
        }
    }

    static func detect(env: [String: String], bundleIdFromProcess: String?) -> Host {
        let bid = env["__CFBundleIdentifier"] ?? bundleIdFromProcess ?? ""
        let known: [(String, String, String)] = [
            ("com.mitchellh.ghostty", "Ghostty", "terminal"),
            ("com.googlecode.iterm2", "iTerm2", "terminal"),
            ("com.apple.Terminal", "Terminal", "terminal"),
            ("net.kovidgoyal.kitty", "kitty", "terminal"),
            ("com.github.wez.wezterm", "WezTerm", "terminal"),
            ("dev.warp.Warp-Stable", "Warp", "terminal"),
            ("co.zeit.hyper", "Hyper", "terminal"),
            ("com.microsoft.VSCode", "VS Code", "chevron.left.forwardslash.chevron.right"),
            ("com.microsoft.VSCodeInsiders", "VS Code", "chevron.left.forwardslash.chevron.right"),
            ("com.todesktop.230313mzl4w4u92", "Cursor", "chevron.left.forwardslash.chevron.right"),
            ("com.exafunction.windsurf", "Windsurf", "chevron.left.forwardslash.chevron.right"),
            ("com.anthropic.claudefordesktop", "Claude Desktop", "sparkles"),
        ]
        for (prefix, name, glyph) in known where bid.hasPrefix(prefix) { return Host(name: name, bundleId: bid, glyph: glyph) }
        if bid.hasPrefix("com.jetbrains.") { return Host(name: "JetBrains", bundleId: bid, glyph: "chevron.left.forwardslash.chevron.right") }
        switch env["TERM_PROGRAM"]?.lowercased() {
        case "ghostty": return Host(name: "Ghostty", bundleId: bid, glyph: "terminal")
        case "iterm.app": return Host(name: "iTerm2", bundleId: bid, glyph: "terminal")
        case "apple_terminal": return Host(name: "Terminal", bundleId: bid, glyph: "terminal")
        case "vscode": return Host(name: "VS Code", bundleId: bid, glyph: "chevron.left.forwardslash.chevron.right")
        case "wezterm": return Host(name: "WezTerm", bundleId: bid, glyph: "terminal")
        case "tmux": return Host(name: "tmux", bundleId: bid, glyph: "terminal")
        default: break
        }
        if env["SSH_CONNECTION"] != nil { return Host(name: "SSH", bundleId: nil, glyph: "network") }
        return .unknown
    }
}

enum Palette {
    /// Session colours from the brand spec: everything except mint, which is reserved for the accent.
    static let colors: [NSColor] = [
        NSColor(srgbRed: 0.910, green: 0.627, blue: 0.298, alpha: 1), // amber   #E8A04C
        NSColor(srgbRed: 0.435, green: 0.659, blue: 0.961, alpha: 1), // blue    #6FA8F5
        NSColor(srgbRed: 0.780, green: 0.608, blue: 0.910, alpha: 1), // lavender #C79BE8
        NSColor(srgbRed: 0.910, green: 0.827, blue: 0.435, alpha: 1), // yellow  #E8D36F
        NSColor(srgbRed: 0.945, green: 0.545, blue: 0.545, alpha: 1), // coral   #F18B8B
        NSColor(srgbRed: 0.373, green: 0.725, blue: 0.839, alpha: 1), // teal    #5FB9D6
    ]
    static func color(for key: String) -> NSColor {
        var h: UInt64 = 1469598103934665603
        for b in key.utf8 { h ^= UInt64(b); h = h &* 1099511628211 }
        return colors[Int(h % UInt64(colors.count))]
    }
}

// MARK: - Pending items

enum ItemKind {
    case permission(tool: String, input: [String: Any], suggestions: [[String: Any]])
    case question(questions: [Question], originalInput: [String: Any])
    case finished(summary: String)
    case info(text: String)

    var isBlocking: Bool {
        switch self { case .permission, .question, .finished: return true; case .info: return false }
    }
}

struct Question {
    let text: String
    let header: String
    let options: [(label: String, description: String)]
    let multiSelect: Bool

    static func parse(_ raw: Any?) -> [Question] {
        guard let arr = raw as? [[String: Any]] else { return [] }
        return arr.map { q in
            let opts = (q["options"] as? [[String: Any]] ?? []).map { o in
                (label: o["label"] as? String ?? "", description: o["description"] as? String ?? "")
            }
            return Question(text: q["question"] as? String ?? "", header: q["header"] as? String ?? "Question",
                            options: opts, multiSelect: q["multiSelect"] as? Bool ?? false)
        }
    }
}

final class PendingItem: Identifiable, ObservableObject {
    let id = UUID()
    let session: Session
    let kind: ItemKind
    let createdAt = Date()
    let connection: HookConnection?       // nil for informational items
    var deadline: Date?                   // when Beckon will passthrough on its own
    @Published var answers: [Int: Set<Int>] = [:]    // question index -> selected option indexes
    @Published var currentQuestion = 0
    @Published var replyText = ""
    @Published var sent = false           // "Sent → …" state
    @Published var sendError: String?     // messaging transport failed (session gone?)

    init(session: Session, kind: ItemKind, connection: HookConnection?, deadline: Date?) {
        self.session = session; self.kind = kind; self.connection = connection; self.deadline = deadline
    }

    var eyebrow: String {
        switch kind {
        case .permission: return "PERMISSION REQUEST"
        case .question(let qs, _): return qs.indices.contains(currentQuestion) ? qs[currentQuestion].header.uppercased() : "QUESTION"
        case .finished: return "FINISHED"
        case .info: return "WAITING"
        }
    }

    var oneLine: String {
        switch kind {
        case .permission(let tool, let input, _): return PermissionSummary.oneLine(tool: tool, input: input, cwd: session.cwd)
        case .question(let qs, _):
            let q = qs.indices.contains(currentQuestion) ? qs[currentQuestion] : qs[0]
            return (qs.count > 1 ? "Question \(currentQuestion + 1) of \(qs.count) · " : "") + q.text
        case .finished(let s): return "Finished" + (s.isEmpty ? "" : " · " + s)
        case .info(let t): return t
        }
    }
}

enum PermissionSummary {
    /// Short imperative title for the active card ("Run a shell command").
    static func title(tool: String) -> String {
        switch tool {
        case "Bash": return "Run a shell command"
        case "Edit", "MultiEdit": return "Edit a file"
        case "Write": return "Write a file"
        case "Read": return "Read a file"
        case "NotebookEdit": return "Edit a notebook"
        case "WebFetch", "WebSearch": return "Access the web"
        case "Agent", "Task": return "Launch a subagent"
        default: return tool.hasPrefix("mcp__") ? "Call an MCP tool" : "Use \(tool)"
        }
    }
    /// One-line form for the waiting list ("Edit src/middleware/rateLimit.ts").
    static func oneLine(tool: String, input: [String: Any], cwd: String? = nil) -> String {
        let c = chip(tool: tool, input: input, cwd: cwd).replacingOccurrences(of: "\n", with: " ")
        switch tool {
        case "Bash": return c
        case "Edit", "MultiEdit": return "Edit " + c
        case "Write": return "Write " + c
        case "Read": return "Read " + c
        default: return title(tool: tool) + (c.isEmpty ? "" : " · " + c)
        }
    }
    /// Short mono hint shown inside the Always button: the tail of the rule ("migrate:*", "middleware/**").
    static func alwaysHint(tool: String, input: [String: Any], suggestions: [[String: Any]], cwd: String) -> String {
        let rules = alwaysRules(tool: tool, input: input, suggestions: suggestions, cwd: cwd)
        guard let r = rules.flatMap({ ($0["rules"] as? [[String: Any]]) ?? [] }).first else { return "" }
        guard var c = r["ruleContent"] as? String else { return "all" }
        c = c.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        if c.hasPrefix("//") || c.hasPrefix("/") || c.hasPrefix("~") {          // path pattern → last two components
            let parts = c.split(separator: "/").filter { !$0.isEmpty }
            c = parts.suffix(2).joined(separator: "/")
        } else if let last = c.split(separator: " ").last {                      // command → last token
            c = String(last)
        }
        if c.count > 18 { c = "…" + c.suffix(17) }
        return c
    }
    /// Footnote under the actions: "Always writes Bash(pnpm prisma migrate:*) to this project".
    static func alwaysFootnote(tool: String, input: [String: Any], suggestions: [[String: Any]], cwd: String) -> (rule: String, where_: String) {
        let rules = alwaysRules(tool: tool, input: input, suggestions: suggestions, cwd: cwd)
        let names = rules.flatMap { ($0["rules"] as? [[String: Any]]) ?? [] }.map(describe)
        let dest = (rules.first?["destination"] as? String) ?? "localSettings"
        let where_ = dest == "localSettings" || dest == "projectSettings" ? "to this project" : dest == "userSettings" ? "to your user settings" : "for this session"
        return (names.joined(separator: ", "), where_)
    }

    static func headline(tool: String) -> String {
        switch tool {
        case "Bash": return "Claude wants to run a command."
        case "Edit", "MultiEdit": return "Claude wants to edit a file."
        case "Write": return "Claude wants to write a file."
        case "Read": return "Claude wants to read a file."
        case "WebFetch", "WebSearch": return "Claude wants to access the web."
        default: return tool.hasPrefix("mcp__") ? "Claude wants to call an MCP tool." : "Claude wants to use \(tool)."
        }
    }
    static func chip(tool: String, input: [String: Any], cwd: String? = nil) -> String {
        if let c = input["command"] as? String { return c.replacingOccurrences(of: "\n", with: " ⏎ ") }
        if let p = input["file_path"] as? String { return relative(p, to: cwd) }
        if let u = input["url"] as? String { return u }
        if let q = input["query"] as? String { return q }
        if let d = input["description"] as? String { return d }
        if let data = try? JSONSerialization.data(withJSONObject: input, options: [.sortedKeys]), let s = String(data: data, encoding: .utf8) {
            return s.count > 140 ? String(s.prefix(140)) + "…" : s
        }
        return ""
    }
    /// Path relative to the project when inside it, else ~-abbreviated.
    static func relative(_ path: String, to cwd: String?) -> String {
        if let cwd, !cwd.isEmpty, path.hasPrefix(cwd + "/") { return String(path.dropFirst(cwd.count + 1)) }
        return abbreviate(path)
    }
    static func abbreviate(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
    static let fileTools: Set<String> = ["Edit", "MultiEdit", "Write", "Read", "NotebookEdit"]
    /// Rule for "always allow": exact command for Bash, project-scoped path pattern for file tools, tool-wide otherwise.
    static func rule(tool: String, input: [String: Any], cwd: String) -> [String: Any] {
        if tool == "Bash", let c = input["command"] as? String { return ["toolName": "Bash", "ruleContent": c] }
        if fileTools.contains(tool) { return ["toolName": tool, "ruleContent": "//" + cwd.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/**"] }
        return ["toolName": tool]
    }
    /// Human-readable form of a rule, e.g. `Bash(npm test)` or `Edit(//Users/me/proj/**)`.
    static func describe(_ rule: [String: Any]) -> String {
        let t = rule["toolName"] as? String ?? "?"
        if let c = rule["ruleContent"] as? String { return "\(t)(\(c))" }
        return t
    }
    /// What "Always" will write for this request: Claude's own addRules suggestions when present, else our rule.
    static func alwaysRules(tool: String, input: [String: Any], suggestions: [[String: Any]], cwd: String) -> [[String: Any]] {
        let fromClaude = suggestions.filter { $0["type"] as? String == "addRules" }
        if !fromClaude.isEmpty { return fromClaude }
        return [["type": "addRules", "rules": [rule(tool: tool, input: input, cwd: cwd)], "behavior": "allow", "destination": "localSettings"]]
    }
    static func describeAlways(tool: String, input: [String: Any], suggestions: [[String: Any]], cwd: String) -> String {
        let rules = alwaysRules(tool: tool, input: input, suggestions: suggestions, cwd: cwd)
        let names = rules.flatMap { ($0["rules"] as? [[String: Any]]) ?? [] }.map(describe)
        let dest = (rules.first?["destination"] as? String) ?? "localSettings"
        let where_ = dest == "localSettings" ? ".claude/settings.local.json in this project" : dest == "projectSettings" ? ".claude/settings.json in this project" : dest == "userSettings" ? "~/.claude/settings.json" : "this session only"
        return "Allow and add rule \(names.joined(separator: ", ")) to \(where_)"
    }
}

// MARK: - Transcript summary

enum Transcript {
    /// Last assistant text in a Claude Code transcript JSONL, trimmed for a card.
    static func lastAssistantText(path: String?, maxChars: Int = 220) -> String {
        guard let path, let fh = FileHandle(forReadingAtPath: path) else { return "" }
        defer { try? fh.close() }
        let size = (try? fh.seekToEnd()) ?? 0
        let tail: UInt64 = 400_000
        let start = size > tail ? size - tail : 0
        try? fh.seek(toOffset: start)
        guard let data = try? fh.readToEnd(), let text = String(data: data, encoding: .utf8) else { return "" }
        for line in text.split(separator: "\n").reversed() {
            guard let d = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  obj["type"] as? String == "assistant",
                  let msg = obj["message"] as? [String: Any],
                  let content = msg["content"] as? [[String: Any]] else { continue }
            let texts = content.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
            guard let t = texts.last?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { continue }
            let flat = t.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .replacingOccurrences(of: "[#*`_>]+", with: "", options: .regularExpression)
            return flat.count > maxChars ? String(flat.prefix(maxChars)).trimmingCharacters(in: .whitespaces) + "…" : flat
        }
        return ""
    }
}

// MARK: - Process tree

enum ProcessTree {
    static func parent(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info.kp_eproc.e_ppid
    }
    /// Walk up from `pid` until we hit a process that is a GUI application.
    static func owningApp(from pid: pid_t) -> NSRunningApplication? {
        var cur: pid_t? = pid
        var hops = 0
        while let p = cur, p > 1, hops < 12 {
            if let app = NSRunningApplication(processIdentifier: p), app.bundleIdentifier != nil, app.activationPolicy != .prohibited { return app }
            cur = parent(of: p); hops += 1
        }
        return nil
    }
}

// MARK: - Settings

enum Prefs {
    static let d = UserDefaults.standard
    static var soundEnabled: Bool { get { d.object(forKey: "soundEnabled") as? Bool ?? true } set { d.set(newValue, forKey: "soundEnabled") } }
    static var showWhenHostInFront: Bool { get { d.bool(forKey: "showWhenHostInFront") } set { d.set(newValue, forKey: "showWhenHostInFront") } }
    static var paused: Bool { get { d.bool(forKey: "paused") } set { d.set(newValue, forKey: "paused") } }
    static var didOnboard: Bool { get { d.bool(forKey: "didOnboard") } set { d.set(newValue, forKey: "didOnboard") } }
    static var checkUpdates: Bool { get { d.object(forKey: "checkUpdates") as? Bool ?? true } set { d.set(newValue, forKey: "checkUpdates") } }
    static var hotkeyKeyCode: UInt32 { get { d.object(forKey: "hotkeyKeyCode") as? UInt32 ?? 49 /* Space */ } set { d.set(newValue, forKey: "hotkeyKeyCode") } }
    static var hotkeyModifiers: UInt32 { get { d.object(forKey: "hotkeyModifiers") as? UInt32 ?? 2048 /* ⌥ */ } set { d.set(newValue, forKey: "hotkeyModifiers") } }
    static var lastUpdateCheck: Date? { get { d.object(forKey: "lastUpdateCheck") as? Date } set { d.set(newValue, forKey: "lastUpdateCheck") } }
    static var skippedVersion: String? { get { d.string(forKey: "skippedVersion") } set { d.set(newValue, forKey: "skippedVersion") } }
}

enum AppInfo {
    static var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev" }
    static var updateFeed: URL? { (Bundle.main.infoDictionary?["BeckonUpdateFeedURL"] as? String).flatMap(URL.init) }
    static var downloadPage: URL? { (Bundle.main.infoDictionary?["BeckonDownloadURL"] as? String).flatMap(URL.init) }
    /// Claude Code versions this build was tested against (major.minor).
    static let testedClaudeMinor = "2.1"
}

/// Finds the `claude` binary and reports its version; GUI apps do not inherit the shell PATH.
enum ClaudeCLI {
    static var cachedVersion: String?
    static func locate() -> String? {
        let home = NSHomeDirectory()
        let candidates = ["\(home)/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude", "\(home)/.claude/local/claude", "\(home)/.npm-global/bin/claude"]
        if let hit = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) { return hit }
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/zsh"); p.arguments = ["-lc", "command -v claude"]
        let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
        guard (try? p.run()) != nil else { return nil }
        p.waitUntilExit()
        let s = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return s.isEmpty ? nil : s
    }
    static func version(completion: @escaping (String?) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            guard let bin = locate() else { DispatchQueue.main.async { completion(nil) }; return }
            let p = Process(); p.executableURL = URL(fileURLWithPath: bin); p.arguments = ["--version"]
            let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
            guard (try? p.run()) != nil else { DispatchQueue.main.async { completion(nil) }; return }
            p.waitUntilExit()
            let raw = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let v = raw.split(separator: " ").first.map(String.init)
            DispatchQueue.main.async { cachedVersion = v; completion(v) }
        }
    }
    /// nil when fine; a short warning when Claude Code is newer than what Beckon was tested with.
    static func compatibilityNote() -> String? {
        guard let v = cachedVersion else { return nil }
        let parts = v.split(separator: ".").map(String.init)
        guard parts.count >= 2 else { return nil }
        let minor = parts[0] + "." + parts[1]
        if minor == AppInfo.testedClaudeMinor { return nil }
        return "Claude Code \(v) is newer than Beckon was tested with (\(AppInfo.testedClaudeMinor).x). Everything still falls back to the terminal if a payload looks unfamiliar."
    }
}

enum Paths {
    static let home = URL(fileURLWithPath: NSHomeDirectory())
    static let beckonDir = home.appendingPathComponent(".beckon")
    static let binDir = beckonDir.appendingPathComponent("bin")
    static let shim = binDir.appendingPathComponent("beckon-hook")
    static let socket = beckonDir.appendingPathComponent("beckon.sock")
    static let log = beckonDir.appendingPathComponent("log.jsonl")
    static let backups = beckonDir.appendingPathComponent("backups")
    static let claudeSettings = home.appendingPathComponent(".claude/settings.json")
}

enum Log {
    static func event(_ dict: [String: Any]) {
        var d = dict; d["ts"] = ISO8601DateFormatter().string(from: Date())
        guard let data = try? JSONSerialization.data(withJSONObject: d, options: [.sortedKeys]) else { return }
        try? FileManager.default.createDirectory(at: Paths.beckonDir, withIntermediateDirectories: true)
        if let size = (try? FileManager.default.attributesOfItem(atPath: Paths.log.path))?[.size] as? Int, size > 5_000_000 {
            let old = Paths.beckonDir.appendingPathComponent("log.1.jsonl")
            try? FileManager.default.removeItem(at: old); try? FileManager.default.moveItem(at: Paths.log, to: old)
        }
        if !FileManager.default.fileExists(atPath: Paths.log.path) { FileManager.default.createFile(atPath: Paths.log.path, contents: nil) }
        if let fh = try? FileHandle(forWritingTo: Paths.log) { defer { try? fh.close() }; _ = try? fh.seekToEnd(); fh.write(data); fh.write("\n".data(using: .utf8)!) }
    }
}
