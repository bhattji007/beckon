import Foundation

/// One hook invocation. Owns the client fd; `reply` is one-shot.
final class HookConnection {
    let fd: Int32
    private let lock = NSLock()
    private var replied = false
    private var hangupSource: DispatchSourceRead?
    /// Called (on main) if the shim goes away before we replied — Claude was interrupted or answered elsewhere.
    var onPeerClosed: (() -> Void)?
    init(fd: Int32) { self.fd = fd }

    func watchForHangup() {
        let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: DispatchQueue.global(qos: .utility))
        src.setEventHandler { [weak self] in
            guard let self else { return }
            var b = [UInt8](repeating: 0, count: 256)
            let n = read(self.fd, &b, b.count)
            if n <= 0 {                       // EOF or error → peer is gone
                self.hangupSource?.cancel(); self.hangupSource = nil
                let wasOpen = self.isOpen
                self.lock.lock(); self.replied = true; self.lock.unlock()
                close(self.fd)
                if wasOpen { DispatchQueue.main.async { self.onPeerClosed?() } }
            }
        }
        src.resume(); hangupSource = src
    }

    /// Send a JSON object (or nothing → passthrough) and close.
    func reply(_ json: [String: Any]?) {
        lock.lock(); defer { lock.unlock() }
        guard !replied else { return }
        replied = true
        hangupSource?.cancel(); hangupSource = nil
        var out = Data()
        if let json, let d = try? JSONSerialization.data(withJSONObject: json, options: [.withoutEscapingSlashes]) { out = d }
        out.append(0x0A)
        out.withUnsafeBytes { buf in
            var off = 0
            while off < buf.count {
                let w = write(fd, buf.baseAddress! + off, buf.count - off)
                if w <= 0 { break }
                off += w
            }
        }
        shutdown(fd, SHUT_RDWR)
        close(fd)
    }
    func passthrough() { reply(nil) }
    var isOpen: Bool { lock.lock(); defer { lock.unlock() }; return !replied }
}

struct HookEnvelope {
    let pid: pid_t
    let ppid: pid_t
    let shimCwd: String
    let env: [String: String]
    let payload: [String: Any]

    var eventName: String { payload["hook_event_name"] as? String ?? "" }
    var sessionId: String { payload["session_id"] as? String ?? "unknown" }
    var cwd: String { payload["cwd"] as? String ?? shimCwd }
}

final class SocketServer {
    private var listenFd: Int32 = -1
    private var source: DispatchSourceRead?
    private let queue = DispatchQueue(label: "beckon.socket", qos: .userInitiated)
    var onEnvelope: ((HookEnvelope, HookConnection) -> Void)?

    func start() throws {
        try FileManager.default.createDirectory(at: Paths.beckonDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        unlink(Paths.socket.path)
        listenFd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listenFd >= 0 else { throw NSError(domain: "beckon", code: 1, userInfo: [NSLocalizedDescriptionKey: "socket() failed"]) }
        var addr = sockaddr_un(); addr.sun_family = sa_family_t(AF_UNIX)
        let path = Paths.socket.path
        let cap = MemoryLayout.size(ofValue: addr.sun_path)
        withUnsafeMutablePointer(to: &addr.sun_path) { p in
            p.withMemoryRebound(to: CChar.self, capacity: cap) { dst in
                _ = path.withCString { strncpy(dst, $0, cap - 1) }
            }
        }
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listenFd, $0, len) } }
        guard bound == 0 else { throw NSError(domain: "beckon", code: 2, userInfo: [NSLocalizedDescriptionKey: "bind() failed: \(String(cString: strerror(errno)))"]) }
        chmod(path, 0o600)
        guard listen(listenFd, 64) == 0 else { throw NSError(domain: "beckon", code: 3, userInfo: [NSLocalizedDescriptionKey: "listen() failed"]) }
        _ = fcntl(listenFd, F_SETFL, fcntl(listenFd, F_GETFL) | O_NONBLOCK)   // accept() must never block the source's queue
        let src = DispatchSource.makeReadSource(fileDescriptor: listenFd, queue: queue)
        src.setEventHandler { [weak self] in self?.acceptLoop() }
        src.resume(); source = src
    }

    func stop() { source?.cancel(); if listenFd >= 0 { close(listenFd) }; unlink(Paths.socket.path) }

    private func acceptLoop() {
        while true {
            let fd = accept(listenFd, nil, nil)
            if fd < 0 { break }                                   // EAGAIN: drained
            _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) & ~O_NONBLOCK)
            // same-uid check
            var cred = xucred(); var credLen = socklen_t(MemoryLayout<xucred>.size)
            if getsockopt(fd, 0, LOCAL_PEERCRED, &cred, &credLen) == 0, cred.cr_uid != getuid() { close(fd); continue }
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in self?.handle(fd: fd) }
        }
    }

    private func handle(fd: Int32) {
        // Read until newline (the shim sends exactly one line then half-closes).
        var data = Data(); var chunk = [UInt8](repeating: 0, count: 65536)
        var deadline = 50
        while deadline > 0 {
            let n = read(fd, &chunk, chunk.count)
            if n > 0 { data.append(chunk, count: n); if chunk[..<n].contains(0x0A) { break } }
            else if n == 0 { break }
            else if errno == EINTR { continue }
            else { break }
            deadline -= 1
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = obj["payload"] as? [String: Any] else {
            let c = HookConnection(fd: fd); c.passthrough(); return
        }
        let env = (obj["env"] as? [String: String]) ?? [:]
        let envelope = HookEnvelope(pid: pid_t(obj["pid"] as? Int ?? 0), ppid: pid_t(obj["ppid"] as? Int ?? 0),
                                    shimCwd: obj["cwd"] as? String ?? "", env: env, payload: payload)
        let conn = HookConnection(fd: fd)
        DispatchQueue.main.async { [weak self] in
            self?.onEnvelope?(envelope, conn)
            if conn.isOpen { conn.watchForHangup() }
        }
    }
}
