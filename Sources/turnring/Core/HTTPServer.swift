#if !os(Windows)
import Foundation
#if canImport(Glibc)
import Glibc
#endif

/// Optional local HTTP endpoint for tools that can't run a command:
/// `POST http://127.0.0.1:<port>/notify` with `Authorization: Bearer <token>` and a JSON body
/// like `{"title": "…", "message": "…", "source": "…", "event": "done", "cwd": "…"}`.
/// It only listens on the loopback interface.
final class HTTPServer {
    struct Body: Decodable {
        var title: String?
        var message: String?
        var source: String?
        var event: String?
        var cwd: String?
    }

    private let port: Int
    private let token: String
    private let handle: (Message) -> String
    private var fd: Int32 = -1

    init(port: Int, token: String, handle: @escaping (Message) -> String) {
        self.port = port
        self.token = token
        self.handle = handle
    }

    func start() throws {
        fd = Posix.streamSocket(AF_INET)
        guard fd >= 0 else { throw SocketServer.StartError.failed("socket") }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &on, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(port).bigEndian)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, listen(fd, 16) == 0 else {
            close(fd)
            throw SocketServer.StartError.failed("port \(port): \(String(cString: strerror(errno)))")
        }
        Thread.detachNewThread { [self] in
            while true {
                let client = accept(fd, nil, nil)
                if client < 0 { if errno == EBADF { return } else { continue } }
                serve(client)
            }
        }
    }

    func stop() {
        if fd >= 0 { close(fd) }
        fd = -1
    }

    private func serve(_ client: Int32) {
        defer { close(client) }
        Posix.configure(client, timeoutMs: 2000)
        var data = Data()
        var buf = [UInt8](repeating: 0, count: 8192)
        var expected: Int?
        while data.count < 256 * 1024 {
            if let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) {
                if expected == nil {
                    let head = String(decoding: data[..<headerEnd.lowerBound], as: UTF8.self)
                    expected = headerEnd.upperBound + (HTTPServer.header("content-length", in: head).flatMap(Int.init) ?? 0)
                }
                if let expected, data.count >= expected { break }
            }
            let n = read(client, &buf, buf.count)
            if n <= 0 { break }
            data.append(contentsOf: buf[0..<n])
        }
        let (status, reply) = respond(to: data)
        let response = "HTTP/1.1 \(status)\r\nContent-Type: text/plain\r\nContent-Length: \(reply.utf8.count + 1)\r\nConnection: close\r\n\r\n\(reply)\n"
        _ = Posix.writeAll(client, Data(response.utf8))
    }

    func respond(to request: Data) -> (String, String) {
        guard let headerEnd = request.range(of: Data("\r\n\r\n".utf8)) else { return ("400 Bad Request", "error bad request") }
        let head = String(decoding: request[..<headerEnd.lowerBound], as: UTF8.self)
        let requestLine = head.components(separatedBy: "\r\n").first ?? ""
        guard requestLine.hasPrefix("POST /notify ") else { return ("404 Not Found", "error use POST /notify") }
        guard HTTPServer.header("authorization", in: head) == "Bearer \(token)" else {
            return ("401 Unauthorized", "error missing or wrong token")
        }
        guard let body = try? JSONDecoder().decode(Body.self, from: request[headerEnd.upperBound...]) else {
            return ("400 Bad Request", "error body must be JSON")
        }
        guard let msg = Message.make(source: body.source, payload: nil, event: body.event, title: body.title,
                                     message: body.message, cwd: body.cwd ?? NSHomeDirectory(), app: nil)
        else { return ("200 OK", "skipped") }
        return ("200 OK", handle(msg))
    }

    static func header(_ name: String, in head: String) -> String? {
        for line in head.components(separatedBy: "\r\n").dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2, parts[0].lowercased() == name {
                return parts[1].trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }
}
#endif
