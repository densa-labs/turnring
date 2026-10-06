import Foundation
#if canImport(Glibc)
import Glibc
#endif

/// Small POSIX helpers so the socket code builds on macOS and Linux.
enum Posix {
    static func streamSocket(_ domain: Int32) -> Int32 {
        #if os(Linux)
        socket(domain, Int32(SOCK_STREAM.rawValue), 0)
        #else
        socket(domain, SOCK_STREAM, 0)
        #endif
    }

    /// Timeouts for reads and writes, and no SIGPIPE when the other side hangs up.
    static func configure(_ fd: Int32, timeoutMs: Int) {
        var tv = timeval(tv_sec: timeoutMs / 1000, tv_usec: .init((timeoutMs % 1000) * 1000))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        #if os(macOS)
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        #else
        signal(SIGPIPE, SIG_IGN)
        #endif
    }

    static func writeAll(_ fd: Int32, _ data: Data) -> Bool {
        data.withUnsafeBytes { raw in
            var offset = 0
            while offset < data.count {
                let n = write(fd, raw.baseAddress! + offset, data.count - offset)
                if n <= 0 { return false }
                offset += n
            }
            return true
        }
    }
}
