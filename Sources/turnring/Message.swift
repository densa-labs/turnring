import Foundation
#if canImport(Glibc)
import Glibc
#endif

/// One notification request, sent from `turnring notify` to the agent as a JSON line.
struct Message: Codable, Equatable {
    var v = 1
    var source: String?
    /// "done", "waiting", or another lowercased hook event name.
    var event: String?
    var title: String
    var subtitle: String?
    /// The banner body, cut to `bodyLimit`.
    var message: String = ""
    /// The whole reply, for "Copy Reply" and ntfy attachments. Nil when it equals `message`.
    var detail: String?
    var cwd: String?
    var app: String?
    /// The controlling terminal of the agent, for focusing the exact tab.
    var tty: String?
    /// The project's repository web page. Worked out by `turnring notify`, which can read
    /// the project folder: the agent may not (Desktop and Documents are privacy-protected).
    var repo: String?
    var ts: String?
}

/// Fields Turnring reads from agent hook payloads (stdin JSON). Claude Code, Codex and
/// Gemini CLI share `hook_event_name` and `cwd`; Cursor sends `workspace_roots` instead.
struct HookPayload: Decodable {
    var hook_event_name: String?
    var cwd: String?
    var workspace_roots: [String]?
    var message: String?
    var last_assistant_message: String? // Claude Code, Codex
    var prompt_response: String?        // Gemini CLI
    var text: String?                   // Cursor afterAgentResponse
    var status: String?                 // Cursor stop: completed | aborted | error
}

extension Message {
    static let bodyLimit = 200
    static let detailLimit = 64 * 1024

    /// Display names for `--source`. Titles name the agent; the project goes in the subtitle.
    static let agentNames = [
        "claude-code": "Claude Code", "codex": "Codex", "cursor": "Cursor",
        "gemini": "Gemini CLI", "aider": "Aider",
    ]

    /// Title and subtitle on one line, for ntfy, history and the Recent menu.
    var fullTitle: String { subtitle.map { "\(title) · \($0)" } ?? title }

    var project: String? { cwd.map { URL(fileURLWithPath: $0).lastPathComponent } }

    /// The full reply when there is one, otherwise the banner body.
    var fullText: String { detail ?? message }

    /// Maps hook event names from every supported agent onto "done" and "waiting".
    static func kind(of event: String) -> String {
        switch event {
        case "Stop", "stop", "AfterAgent", "done": "done"
        case "Notification", "PermissionRequest", "waiting": "waiting"
        default: event.lowercased()
        }
    }

    /// Builds the message from a hook payload or `--event`. Explicit `--title`/`--message` win.
    static func make(source: String?, payload: HookPayload?, event: String? = nil, title: String?, message: String?,
                     cwd: String, app: String?, tty: String? = nil, repo: String? = nil,
                     now: Date = Date()) -> Message {
        let dir = payload?.cwd ?? payload?.workspace_roots?.first ?? cwd
        let project = URL(fileURLWithPath: dir).lastPathComponent
        let agent = source.flatMap { agentNames[$0] }
        // "Done · Codex" with the project as subtitle, or "Done · project" for other sources.
        let who = agent ?? project
        let rawEvent = payload?.hook_event_name ?? event
        let kind = rawEvent.map(Message.kind(of:))
        var derivedTitle = "Turnring"
        var derivedBody = ""
        switch kind {
        case "done":
            let stopped = payload?.status.map { $0 != "completed" } ?? false
            derivedTitle = "\(stopped ? "Stopped" : "Done") · \(who)"
            derivedBody = payload?.last_assistant_message ?? payload?.prompt_response ?? payload?.text ?? ""
        case "waiting":
            derivedTitle = "Waiting · \(who)"
            derivedBody = payload?.message ?? ""
        case .some:
            derivedTitle = "\(rawEvent!) · \(who)"
        case nil:
            break
        }
        let full = String(plainText(message ?? derivedBody).prefix(detailLimit))
        let body = full.count > bodyLimit ? String(full.prefix(bodyLimit - 1)) + "…" : full
        return Message(
            source: source,
            event: kind,
            title: title ?? derivedTitle,
            subtitle: title == nil && agent != nil && kind != nil ? project : nil,
            message: body,
            detail: full == body ? nil : full,
            cwd: dir,
            app: app,
            tty: tty,
            repo: repo,
            ts: ISO8601DateFormatter().string(from: now)
        )
    }

    /// Strips the Markdown agents write so banners read as plain text.
    static func plainText(_ markdown: String) -> String {
        var lines: [String] = []
        for raw in markdown.components(separatedBy: .newlines) {
            var line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") { continue }
            while line.hasPrefix("#") { line.removeFirst() }
            if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
                line = "• " + line.dropFirst(2)
            }
            if line.hasPrefix(">") { line = String(line.dropFirst()) }
            lines.append(line.trimmingCharacters(in: .whitespaces))
        }
        var text = lines.joined(separator: "\n")
        // [label](url) -> label
        text = text.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]+\)"#, with: "$1", options: .regularExpression)
        for marker in ["**", "__", "`", "~~"] { text = text.replacingOccurrences(of: marker, with: "") }
        // *emphasis* -> emphasis, leaving lone asterisks (like 2 * 3) alone
        text = text.replacingOccurrences(of: #"(?<![\w*])\*(\S[^*\n]*?\S|\S)\*(?![\w*])"#, with: "$1",
                                         options: .regularExpression)
        text = text.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The app to bring forward when the banner is clicked: the one the hook ran under.
    static func captureApp(env: [String: String]) -> String? {
        if let id = env["__CFBundleIdentifier"], !id.isEmpty, id != Prefs.bundleID { return id }
        let byTermProgram = [
            "Apple_Terminal": "com.apple.Terminal",
            "iTerm.app": "com.googlecode.iterm2",
            "ghostty": "com.mitchellh.ghostty",
            "vscode": "com.microsoft.VSCode",
            "WezTerm": "com.github.wez.wezterm",
            "WarpTerminal": "dev.warp.Warp-Stable",
        ]
        return env["TERM_PROGRAM"].flatMap { byTermProgram[$0] }
    }

    /// The terminal device the agent runs in (inherited by this hook process), like "/dev/ttys003".
    static func captureTTY() -> String? {
        #if os(macOS)
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return nil }
        let dev = info.kp_eproc.e_tdev
        guard dev != -1, let name = devname(dev, S_IFCHR) else { return nil }
        return "/dev/" + String(cString: name)
        #else
        guard let name = ttyname(STDERR_FILENO) else { return nil }
        return String(cString: name)
        #endif
    }
}
