#if !os(Windows)
import Foundation

/// Listens on the Unix socket. Each connection carries one JSON line and gets one reply line:
/// `ok`, `paused` or `error <reason>`. `handle` runs on the accept thread.
final class SocketServer {
    private let path: String
    private let handle: (Message) -> String
    private var fd: Int32 = -1

    init(path: String, handle: @escaping (Message) -> String) {
        self.path = path
        self.handle = handle
    }

    enum StartError: Error { case alreadyRunning, failed(String) }

    func start() throws {
        // A live socket means another agent is running; a dead one is left over from a crash.
        if NotifyCommand.send(Data("{}\n".utf8), to: path, timeoutMs: 200) != nil { throw StartError.alreadyRunning }
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                                withIntermediateDirectories: true)
        unlink(path)

        fd = Posix.streamSocket(AF_UNIX)
        guard fd >= 0, var addr = unixAddress(path) else { throw StartError.failed("socket") }
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0 else { throw StartError.failed("bind: \(String(cString: strerror(errno)))") }
        chmod(path, 0o600)
        guard listen(fd, 16) == 0 else { throw StartError.failed("listen") }

        Thread.detachNewThread { [self] in acceptLoop() }
    }

    private func acceptLoop() {
        while true {
            let client = accept(fd, nil, nil)
            if client < 0 { continue }
            serve(client)
        }
    }

    private func serve(_ client: Int32) {
        defer { close(client) }
        Posix.configure(client, timeoutMs: 1000)

        var data = Data()
        var buf = [UInt8](repeating: 0, count: 4096)
        while data.count < 64 * 1024, !data.contains(0x0A) {
            let n = read(client, &buf, buf.count)
            if n <= 0 { break }
            data.append(contentsOf: buf[0..<n])
        }
        let line = data.split(separator: 0x0A, maxSplits: 1).first ?? Data()

        let reply: String
        if let msg = try? JSONDecoder().decode(Message.self, from: line) {
            reply = handle(msg)
        } else {
            reply = "error bad message"
        }
        _ = Posix.writeAll(client, Data((reply + "\n").utf8))
    }
}
#endif
