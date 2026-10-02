import AppKit
import Foundation

/// Installs the hook shim and merges Beckon's hook entries into ~/.claude/settings.json.
/// Never removes or reorders other hooks; backs the file up first; idempotent.
enum Installer {
    static let command = "\"$HOME/.beckon/bin/beckon-hook\""

    /// (event, matcher, timeout seconds)
    static let hooks: [(String, String?, Int)] = [
        ("PermissionRequest", "", 600),
        ("PreToolUse", "AskUserQuestion", 600),
        ("Stop", nil, 60),
        ("Notification", "", 10),
        ("UserPromptSubmit", nil, 5),
        ("SessionStart", nil, 5),
        ("SessionEnd", nil, 5),
        ("SubagentStart", nil, 5),
        ("SubagentStop", nil, 5),
    ]

    enum Status { case installed, partial(missing: [String]), notInstalled, noShim }

    static func status() -> Status {
        guard FileManager.default.isExecutableFile(atPath: Paths.shim.path) else { return .noShim }
        guard let root = readSettings() else { return .notInstalled }
        let present = Set(installedEvents(in: root))
        let missing = hooks.map(\.0).filter { !present.contains($0) }
        if missing.isEmpty { return .installed }
        if missing.count == hooks.count { return .notInstalled }
        return .partial(missing: missing)
    }

    static func installedEvents(in root: [String: Any]) -> [String] {
        guard let hooksDict = root["hooks"] as? [String: Any] else { return [] }
        return hooksDict.compactMap { (event, groups) in
            guard let groups = groups as? [[String: Any]] else { return nil }
            return groups.contains(where: containsBeckon) ? event : nil
        }
    }

    private static func containsBeckon(_ group: [String: Any]) -> Bool {
        ((group["hooks"] as? [[String: Any]]) ?? []).contains { ($0["command"] as? String)?.contains("beckon-hook") == true }
    }

    static func readSettings() -> [String: Any]? {
        guard let data = try? Data(contentsOf: Paths.claudeSettings) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// Human-readable preview of what install will add.
    static func previewText() -> String {
        hooks.map { e, m, t in "• \(e)\(m.map { $0.isEmpty ? "" : " (matcher: \($0))" } ?? "")  → beckon-hook, timeout \(t)s" }.joined(separator: "\n")
    }

    static func installShim() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: Paths.binDir, withIntermediateDirectories: true)
        guard let src = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("beckon-hook"),
              fm.fileExists(atPath: src.path) else {
            throw NSError(domain: "beckon", code: 10, userInfo: [NSLocalizedDescriptionKey: "beckon-hook binary is missing from the app bundle."])
        }
        let srcData = try Data(contentsOf: src)
        if let cur = try? Data(contentsOf: Paths.shim), cur == srcData { return }
        if fm.fileExists(atPath: Paths.shim.path) { try fm.removeItem(at: Paths.shim) }
        try srcData.write(to: Paths.shim)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: Paths.shim.path)
    }

    static func install() throws {
        try installShim()
        let fm = FileManager.default
        var root = readSettings() ?? [:]
        if fm.fileExists(atPath: Paths.claudeSettings.path) {
            try fm.createDirectory(at: Paths.backups, withIntermediateDirectories: true)
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            try? fm.copyItem(at: Paths.claudeSettings, to: Paths.backups.appendingPathComponent("settings-\(stamp).json"))
        }
        var hooksDict = root["hooks"] as? [String: Any] ?? [:]
        for (event, matcher, timeout) in hooks {
            var groups = hooksDict[event] as? [[String: Any]] ?? []
            if groups.contains(where: containsBeckon) { continue }
            var group: [String: Any] = ["hooks": [["type": "command", "command": command, "timeout": timeout]]]
            if let matcher { group["matcher"] = matcher }
            groups.append(group)
            hooksDict[event] = groups
        }
        root["hooks"] = hooksDict
        try write(root)
        Log.event(["kind": "install"])
    }

    static func uninstall() throws {
        guard var root = readSettings(), var hooksDict = root["hooks"] as? [String: Any] else { return }
        for (event, groups) in hooksDict {
            guard var groups = groups as? [[String: Any]] else { continue }
            groups.removeAll(where: containsBeckon)
            if groups.isEmpty { hooksDict.removeValue(forKey: event) } else { hooksDict[event] = groups }
        }
        root["hooks"] = hooksDict
        try write(root)
        Log.event(["kind": "uninstall"])
    }

    private static func write(_ root: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try FileManager.default.createDirectory(at: Paths.claudeSettings.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: Paths.claudeSettings, options: .atomic)
    }
}
