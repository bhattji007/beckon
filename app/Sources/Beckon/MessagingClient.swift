import Foundation

/// Sends a follow-up into a running Claude Code session through its cross-session messaging socket.
/// Wire format (from Claude Code's own debug output): newline-delimited JSON —
///   {"type":"auth","token":"…"}            (required or optional depending on the session's config)
///   {"type":"user","message":{"role":"user","content":"…"}}
enum MessagingClient {
    enum Failure: Error, LocalizedError {
        case noSocket, connect(String), write(String)
        var errorDescription: String? {
            switch self {
            case .noSocket: return "This session has no messaging socket."
            case .connect(let m): return "Session is not reachable (\(m))."
            case .write(let m): return "Could not deliver (\(m))."
            }
        }
    }

    static func send(_ text: String, to session: Session, completion: @escaping (Result<Void, Failure>) -> Void) {
        guard let path = session.messagingSocket else { completion(.failure(.noSocket)); return }
        let token = session.messagingToken
        DispatchQueue.global(qos: .userInitiated).async {
            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0 else { DispatchQueue.main.async { completion(.failure(.connect("socket()"))) }; return }
            defer { close(fd) }
            var addr = sockaddr_un(); addr.sun_family = sa_family_t(AF_UNIX)
            let cap = MemoryLayout.size(ofValue: addr.sun_path)
            withUnsafeMutablePointer(to: &addr.sun_path) { p in p.withMemoryRebound(to: CChar.self, capacity: cap) { dst in _ = path.withCString { strncpy(dst, $0, cap - 1) } } }
            var tv = timeval(tv_sec: 3, tv_usec: 0)
            setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
            let ok = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
            guard ok == 0 else { let m = String(cString: strerror(errno)); DispatchQueue.main.async { completion(.failure(.connect(m))) }; return }

            var lines: [[String: Any]] = []
            if let token, !token.isEmpty { lines.append(["type": "auth", "token": token]) }
            lines.append(["type": "user", "message": ["role": "user", "content": text]])
            var payload = Data()
            for l in lines { if let d = try? JSONSerialization.data(withJSONObject: l) { payload.append(d); payload.append(0x0A) } }
            let written: Bool = payload.withUnsafeBytes { buf in
                var off = 0
                while off < buf.count { let w = write(fd, buf.baseAddress! + off, buf.count - off); if w <= 0 { return false }; off += w }
                return true
            }
            guard written else { let m = String(cString: strerror(errno)); DispatchQueue.main.async { completion(.failure(.write(m))) }; return }
            // The server sends no ack (a "hold" receipt at most). Report success as soon as the bytes are written,
            // then linger very briefly in case a receipt arrives, purely for the log.
            DispatchQueue.main.async { completion(.success(())) }
            var tvShort = timeval(tv_sec: 0, tv_usec: 250_000)
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tvShort, socklen_t(MemoryLayout<timeval>.size))
            var b = [UInt8](repeating: 0, count: 1024); let n = read(fd, &b, b.count)
            if n > 0, let receipt = String(bytes: b[0..<n], encoding: .utf8) { Log.event(["kind": "messaging-receipt", "session": session.id, "receipt": receipt.trimmingCharacters(in: .whitespacesAndNewlines)]) }
        }
    }
}
