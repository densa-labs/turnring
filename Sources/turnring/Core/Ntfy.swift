import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Sends one push per message to every ntfy topic, alongside the native banner. No retries.
enum Ntfy {
    /// Turns ntfy on, keeping existing topics. Returns the first topic.
    @discardableResult
    static func enable(topic: String? = nil) -> String {
        if let topic {
            if !Prefs.ntfyTopics.contains(topic) { Prefs.ntfyTopics = [topic] }
        } else if Prefs.ntfyTopics.isEmpty {
            Prefs.ntfyTopics = [randomTopic()]
        }
        Prefs.ntfyEnabled = true
        return Prefs.ntfyTopics[0]
    }

    /// Anyone who guesses a topic on public ntfy.sh can read it, so default to a random one.
    static func randomTopic() -> String {
        "turnring-" + UUID().uuidString.lowercased().prefix(13)
    }

    /// `completion` runs once every topic has answered (or failed).
    static func send(_ msg: Message, completion: (() -> Void)? = nil) {
        guard Prefs.ntfyEnabled, let server = URL(string: Prefs.ntfyServer) else { completion?(); return }
        let group = DispatchGroup()
        for topic in Prefs.ntfyTopics {
            guard let request = request(for: msg, topic: topic, server: server) else { continue }
            group.enter()
            URLSession.shared.dataTask(with: request) { _, response, error in
                defer { group.leave() }
                if let error {
                    NSLog("turnring: ntfy failed: \(error.localizedDescription)")
                } else if let http = response as? HTTPURLResponse, http.statusCode >= 300 {
                    NSLog("turnring: ntfy returned HTTP \(http.statusCode)")
                }
            }.resume()
        }
        group.notify(queue: .global()) { completion?() }
    }

    static func request(for msg: Message, topic: String, server: URL) -> URLRequest? {
        let title = msg.fullTitle
        let priority = msg.needsAttention && Prefs.ntfyUrgentWaiting ? 4 : 3
        let click = Prefs.ntfyClickRepo ? msg.repo : nil
        let tags = ["waiting": "hourglass", "done": "white_check_mark", "limit": "no_entry", "error": "warning"][msg.event ?? ""]

        if Prefs.ntfyAttachReply, let detail = msg.detail {
            // A long reply goes as the request body, which ntfy stores as an attachment.
            var request = URLRequest(url: server.appendingPathComponent(topic), timeoutInterval: 10)
            request.httpMethod = "PUT"
            request.httpBody = Data(detail.utf8)
            request.setValue("reply.txt", forHTTPHeaderField: "Filename")
            request.setValue(encodedHeader(title), forHTTPHeaderField: "Title")
            request.setValue(encodedHeader(msg.message.isEmpty ? title : msg.message), forHTTPHeaderField: "Message")
            request.setValue(String(priority), forHTTPHeaderField: "Priority")
            if let click { request.setValue(click, forHTTPHeaderField: "Click") }
            if let tags { request.setValue(tags, forHTTPHeaderField: "Tags") }
            return request
        }

        // JSON publishing keeps non-ASCII titles intact.
        var body: [String: Any] = ["topic": topic, "message": msg.message.isEmpty ? title : msg.message,
                                   "priority": priority]
        if !msg.message.isEmpty { body["title"] = title }
        if let click { body["click"] = click }
        if let tags { body["tags"] = [tags] }
        var request = URLRequest(url: server, timeoutInterval: 5)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return request
    }

    /// RFC 2047 encoding, which ntfy accepts for UTF-8 header values like "Done · Codex".
    static func encodedHeader(_ value: String) -> String {
        value.unicodeScalars.allSatisfy(\.isASCII) && !value.contains("\n")
            ? value : "=?UTF-8?B?\(Data(value.utf8).base64EncodedString())?="
    }

    /// The web page of the project's `origin` remote, such as https://github.com/owner/repo.
    static func repoURL(for cwd: String) -> String? {
        var dir = URL(fileURLWithPath: cwd)
        while dir.path != "/" {
            let config = dir.appendingPathComponent(".git/config")
            if let text = try? String(contentsOf: config, encoding: .utf8) { return webURL(fromGitConfig: text) }
            dir.deleteLastPathComponent()
        }
        return nil
    }

    static func webURL(fromGitConfig text: String) -> String? {
        var inOrigin = false
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") { inOrigin = trimmed == "[remote \"origin\"]"; continue }
            guard inOrigin, trimmed.hasPrefix("url") else { continue }
            var url = trimmed.split(separator: "=", maxSplits: 1).last.map {
                $0.trimmingCharacters(in: .whitespaces)
            } ?? ""
            if url.hasSuffix(".git") { url.removeLast(4) }
            if url.hasPrefix("git@"), let colon = url.firstIndex(of: ":") {
                // git@github.com:owner/repo -> https://github.com/owner/repo
                url = "https://" + url[url.index(url.startIndex, offsetBy: 4)..<colon] + "/" + url[url.index(after: colon)...]
            } else if url.hasPrefix("ssh://git@") {
                url = "https://" + url.dropFirst("ssh://git@".count)
            }
            if let at = url.range(of: "@"), url.hasPrefix("https://") {
                url = "https://" + url[at.upperBound...] // drop credentials
            }
            return url.hasPrefix("https://") ? url : nil
        }
        return nil
    }
}

/// `turnring ntfy [topic] [--server URL]`, `turnring ntfy add|remove <topic>`,
/// `turnring ntfy list` and `turnring ntfy off`.
enum NtfyCommand {
    static let usage = "usage: turnring ntfy [topic] [--server URL] | add <topic> | remove <topic> | list | off"

    static func run(_ args: [String]) -> Int32 {
        switch args.first {
        case "off":
            Prefs.ntfyEnabled = false
            print("ntfy is off")
            return 0
        case "list":
            for topic in Prefs.ntfyTopics { print("\(Prefs.ntfyServer)/\(topic)") }
            print(Prefs.ntfyEnabled ? "ntfy is on" : "ntfy is off")
            return 0
        case "add" where args.count == 2:
            if !Prefs.ntfyTopics.contains(args[1]) { Prefs.ntfyTopics.append(args[1]) }
            Prefs.ntfyEnabled = true
            print("Pushes now go to: \(Prefs.ntfyTopics.joined(separator: ", "))")
            return 0
        case "remove" where args.count == 2:
            Prefs.ntfyTopics.removeAll { $0 == args[1] }
            if Prefs.ntfyTopics.isEmpty { Prefs.ntfyEnabled = false }
            print("Pushes now go to: \(Prefs.ntfyTopics.isEmpty ? "nowhere" : Prefs.ntfyTopics.joined(separator: ", "))")
            return 0
        default:
            break
        }
        var topic: String?, server: String?
        var i = 0
        while i < args.count {
            if args[i] == "--server", i + 1 < args.count {
                server = args[i + 1]
                i += 2
            } else if !args[i].hasPrefix("-"), topic == nil {
                topic = args[i]
                i += 1
            } else {
                warn(usage)
                return 64
            }
        }
        if let server {
            guard let url = URL(string: server), url.scheme == "https" || url.scheme == "http" else {
                warn("--server must be an http(s) URL")
                return 64
            }
            Prefs.ntfyServer = server
        }
        let chosen = Ntfy.enable(topic: topic)
        print("ntfy is on: \(Prefs.ntfyServer)/\(chosen)")
        print("Subscribe to that topic in the ntfy app to get pushes on your phone.")
        return 0
    }
}
