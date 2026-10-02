import AppKit
import Foundation

/// Lightweight update notifier: fetches a JSON feed, compares semver, offers the download link. Never installs anything.
final class UpdateChecker {
    static let shared = UpdateChecker()
    struct Release { let version: String; let url: URL; let notes: String }
    private(set) var available: Release?
    var onChange: (() -> Void)?

    func checkIfDue() {
        guard Prefs.checkUpdates, AppInfo.updateFeed != nil else { return }
        if let last = Prefs.lastUpdateCheck, Date().timeIntervalSince(last) < 20 * 3600 { return }
        check(manual: false)
    }

    func check(manual: Bool) {
        guard let feed = AppInfo.updateFeed else { if manual { Self.alert("No update feed is configured in this build.") }; return }
        var req = URLRequest(url: feed); req.cachePolicy = .reloadIgnoringLocalCacheData; req.timeoutInterval = 10
        req.setValue("Beckon/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { [weak self] data, _, err in
            DispatchQueue.main.async {
                guard let self else { return }
                Prefs.lastUpdateCheck = Date()
                guard let data, err == nil, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let v = obj["version"] as? String, let u = (obj["url"] as? String).flatMap(URL.init) else {
                    if manual { Self.alert("Could not reach the update feed. \(err?.localizedDescription ?? "")") }
                    return
                }
                let rel = Release(version: v, url: u, notes: obj["notes"] as? String ?? "")
                if Self.isNewer(v, than: AppInfo.version) {
                    self.available = rel; self.onChange?()
                    if manual || Prefs.skippedVersion != v { self.offer(rel, manual: manual) }
                } else {
                    self.available = nil; self.onChange?()
                    if manual { Self.alert("Beckon \(AppInfo.version) is up to date.") }
                }
                Log.event(["kind": "update-check", "latest": v, "current": AppInfo.version])
            }
        }.resume()
    }

    private func offer(_ r: Release, manual: Bool) {
        let a = NSAlert(); a.messageText = "Beckon \(r.version) is available"
        a.informativeText = (r.notes.isEmpty ? "" : r.notes + "\n\n") + "You have \(AppInfo.version). Download the new version and drag it to Applications; your hooks and settings are kept."
        a.addButton(withTitle: "Download"); a.addButton(withTitle: "Later"); if !manual { a.addButton(withTitle: "Skip this version") }
        NSApp.activate(ignoringOtherApps: true)
        switch a.runModal() {
        case .alertFirstButtonReturn: NSWorkspace.shared.open(r.url)
        case .alertThirdButtonReturn: Prefs.skippedVersion = r.version
        default: break
        }
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        func parts(_ s: String) -> [Int] { s.split(separator: "-").first!.split(separator: ".").map { Int($0) ?? 0 } }
        let x = parts(a), y = parts(b)
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }
    static func alert(_ text: String) { let a = NSAlert(); a.messageText = text; NSApp.activate(ignoringOtherApps: true); a.runModal() }
}
