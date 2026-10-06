import Foundation

/// `turnring notify`: build one message and hand it to the running agent.
/// It runs inside agent hooks, so it never fails the hook: it always exits 0 and
/// gives up on the socket after 500 ms.
enum NotifyCommand {
    static func run(_ args: [String]) {
        var title: String?, message: String?, source: String?, event: String?, readStdin = false
        var i = 0
        func value() -> String? {
            i += 1
            return i < args.count ? args[i] : nil
        }
        while i < args.count {
            switch args[i] {
            case "--title": title = value()
            case "--message": message = value()
            case "--source": source = value()
            case "--event": event = value()
            case "--stdin": readStdin = true
            default: warn("ignoring unknown argument \(args[i])")
            }
            i += 1
        }

        var payload: HookPayload?
        if readStdin {
            let data = FileHandle.standardInput.readDataToEndOfFile()
            payload = HookPayload.parse(data)
            if payload == nil, !data.isEmpty { warn("stdin is not a hook payload; using flags only") }
        }

        let env = ProcessInfo.processInfo.environment
        // Grok Build also runs the hooks it finds in Claude Code's and Cursor's settings.
        // Only its own hook speaks for it, so those copies would be duplicates.
        if env["GROK_HOOK_EVENT"] != nil, source != "grok" { return }
        let cwd = payload?.cwd ?? FileManager.default.currentDirectoryPath
        guard let msg = Message.make(source: source, payload: payload, event: event, title: title, message: message,
                                     cwd: FileManager.default.currentDirectoryPath,
                                     app: Message.captureApp(env: env), tty: Message.captureTTY(),
                                     repo: Ntfy.repoURL(for: cwd)) else { return }
        #if os(Windows)
        // There is no menu bar agent on Windows: show the toast and push from here.
        WindowsDelivery.deliver(msg)
        #else
        guard var line = try? JSONEncoder().encode(msg) else { return }
        line.append(0x0A)

        switch send(line, to: Prefs.socketPath, timeoutMs: 500) {
        case .some("ok"), .some("paused"), .some("muted"), .some("quiet"): break
        case .some(let reply): warn("agent replied: \(reply)")
        case .none: warn("Turnring is not running (start it with `brew services start turnring` or open Turnring.app)")
        }
        #endif
    }

    #if !os(Windows)
    /// Writes one line and returns the agent's one-line reply, or nil if it can't be reached in time.
    static func send(_ line: Data, to path: String, timeoutMs: Int) -> String? {
        let fd = Posix.streamSocket(AF_UNIX)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        Posix.configure(fd, timeoutMs: timeoutMs)

        guard var addr = unixAddress(path) else { return nil }
        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { return nil }
        guard Posix.writeAll(fd, line) else { return nil }

        var buf = [UInt8](repeating: 0, count: 256)
        let n = read(fd, &buf, buf.count)
        guard n > 0 else { return nil }
        return String(decoding: buf[0..<n], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    #endif
}

#if !os(Windows)
func unixAddress(_ path: String) -> sockaddr_un? {
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(path.utf8)
    guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { return nil }
    withUnsafeMutableBytes(of: &addr.sun_path) { raw in
        raw.copyBytes(from: bytes)
        raw[bytes.count] = 0
    }
    return addr
}

#endif

func warn(_ text: String) {
    FileHandle.standardError.write(Data("turnring: \(text)\n".utf8))
}
