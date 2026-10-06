import Foundation

/// Sends one push per message to ntfy, alongside the native banner. No retries.
enum Ntfy {
    static func send(title: String, message: String) {
        guard Prefs.ntfyEnabled, let topic = Prefs.ntfyTopic,
              let url = URL(string: Prefs.ntfyServer) else { return }
        // JSON publishing keeps non-ASCII titles intact (HTTP headers can't carry "·").
        var body: [String: String] = ["topic": topic, "message": message.isEmpty ? title : message]
        if !message.isEmpty { body["title"] = title }
        var request = URLRequest(url: url, timeoutInterval: 5)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(body)
        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error {
                NSLog("turnring: ntfy failed: \(error.localizedDescription)")
            } else if let http = response as? HTTPURLResponse, http.statusCode >= 300 {
                NSLog("turnring: ntfy returned HTTP \(http.statusCode)")
            }
        }.resume()
    }
}

/// `turnring ntfy [topic] [--server URL]` turns ntfy on; `turnring ntfy off` turns it off.
enum NtfyCommand {
    static func run(_ args: [String]) -> Int32 {
        if args.first == "off" {
            Prefs.ntfyEnabled = false
            print("ntfy is off")
            return 0
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
                warn("usage: turnring ntfy [topic] [--server URL] | turnring ntfy off")
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
        // Anyone who guesses a topic on public ntfy.sh can read it, so default to a random one.
        let chosen = topic ?? Prefs.ntfyTopic ?? "turnring-" + UUID().uuidString.lowercased().prefix(13)
        Prefs.ntfyTopic = chosen
        Prefs.ntfyEnabled = true
        print("ntfy is on: \(Prefs.ntfyServer)/\(chosen)")
        print("Subscribe to that topic in the ntfy app to get pushes on your phone.")
        return 0
    }
}
