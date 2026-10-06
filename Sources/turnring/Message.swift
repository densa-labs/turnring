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

/// The parts of an agent's hook payload (stdin JSON) Turnring uses. Agents name the same
/// things differently (`hook_event_name`, `hookEventName`, `workspace_roots`, …), so the
/// payload is read loosely from a dictionary.
struct HookPayload {
    var event: String?
    var cwd: String?
    var message: String?
    var notificationType: String?
    var lastMessage: String?
    var status: String?             // Cursor stop: completed | aborted | error
    var terminationReason: String?  // Antigravity: model_stop | max_steps_exceeded | error
    var error: String?
    var errorType: String?          // Claude Code StopFailure: rate_limit, billing_error, …
    var toolName: String?
    var toolCommand: String?

    static func parse(_ data: Data) -> HookPayload? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        func string(_ keys: String...) -> String? {
            for key in keys { if let value = root[key] as? String, !value.isEmpty { return value } }
            return nil
        }
        var payload = HookPayload()
        payload.event = string("hook_event_name", "hookEventName")
        payload.cwd = string("cwd")
            ?? (root["workspace_roots"] as? [String])?.first
            ?? (root["workspacePaths"] as? [String])?.first
            ?? string("workspaceRoot")
        payload.message = string("message")
        payload.notificationType = string("notification_type", "notificationType")
        payload.lastMessage = string("last_assistant_message", "lastAssistantMessage", "prompt_response", "text")
        payload.status = string("status")
        payload.terminationReason = string("terminationReason", "termination_reason")
        payload.error = string("error")
        payload.errorType = string("error_type", "errorType")
        payload.toolName = string("tool_name", "toolName")
        let input = (root["tool_input"] ?? root["toolInput"]) as? [String: Any]
        if let command = input?["command"] ?? input?["cmd"] {
            payload.toolCommand = (command as? String) ?? (command as? [String])?.joined(separator: " ")
        }
        return payload
    }
}

extension Message {
    static let bodyLimit = 200
    static let detailLimit = 64 * 1024

    /// Display names for `--source`. Titles name the agent; the project goes in the subtitle.
    static let agentNames = [
        "claude-code": "Claude Code", "codex": "Codex", "cursor": "Cursor", "gemini": "Gemini CLI",
        "aider": "Aider", "antigravity": "Antigravity", "grok": "Grok Build",
    ]

    /// Event kinds rules and ntfy priorities work with.
    static let kinds = ["done", "waiting", "limit", "error"]

    /// Title and subtitle on one line, for ntfy, history and the Recent menu.
    var fullTitle: String { subtitle.map { "\(title) · \($0)" } ?? title }

    var project: String? { cwd.map { URL(fileURLWithPath: $0).lastPathComponent } }

    /// The full reply when there is one, otherwise the banner body.
    var fullText: String { detail ?? message }

    /// Whether the user should act: approve something, answer, or deal with a limit.
    var needsAttention: Bool { event == "waiting" || event == "limit" || event == "error" }

    /// What happened, as (kind, title word, body), for every agent's hook events.
    /// Returns nil for events Turnring stays quiet about.
    static func classify(_ rawEvent: String, _ p: HookPayload?) -> (kind: String, word: String, body: String)? {
        let errorType = (p?.errorType ?? "").lowercased()
        let limitWords = ["rate_limit", "billing", "quota", "usage_limit", "limit", "overloaded"]
        switch rawEvent {
        case "Stop", "stop", "AfterAgent", "done":
            switch p?.terminationReason {
            case "max_steps_exceeded": return ("limit", "Limit hit", p?.error ?? "The agent reached its step limit.")
            case "error": return ("error", "Error", p?.error ?? "")
            default: break
            }
            if let status = p?.status, status != "completed" {
                return status == "error" ? ("error", "Error", p?.error ?? "") : ("done", "Stopped", "")
            }
            return ("done", "Done", p?.lastMessage ?? "")
        case "StopFailure", "limit", "error":
            let isLimit = rawEvent == "limit" || limitWords.contains { errorType.contains($0) }
                || (p?.error ?? "").lowercased().contains("limit")
            return isLimit ? ("limit", "Limit hit", p?.error ?? "Usage or rate limit reached.")
                : ("error", "Error", p?.error ?? "The turn ended with an error.")
        case "PermissionRequest":
            if p?.toolName == "ExitPlanMode" { return ("waiting", "Plan ready", "Review and approve the plan.") }
            var body = p?.message ?? ""
            if let tool = p?.toolName { body = "Allow \(tool)?" }
            if let command = p?.toolCommand { body = "Run: \(command)" }
            return ("waiting", "Approve", body)
        case "Notification", "waiting":
            let type = (p?.notificationType ?? "").lowercased()
            let text = p?.message ?? ""
            if type == "agent_completed" || type == "auth_success" || type == "elicitation_complete" { return nil }
            if type.hasPrefix("quota") { return ("limit", "Limit hit", text) }
            if type == "permission_prompt" || type == "toolpermission" {
                return ("waiting", text.localizedCaseInsensitiveContains("plan") ? "Plan ready" : "Approve", text)
            }
            if type.hasPrefix("elicitation") { return ("waiting", "Question", text) }
            return ("waiting", "Waiting", text)
        default:
            return (rawEvent.lowercased(), rawEvent, p?.message ?? "")
        }
    }

    /// Builds the message from a hook payload or `--event`. Explicit `--title`/`--message` win.
    /// Returns nil when the event isn't worth a notification.
    static func make(source: String?, payload: HookPayload?, event: String? = nil, title: String?, message: String?,
                     cwd: String, app: String?, tty: String? = nil, repo: String? = nil,
                     now: Date = Date()) -> Message? {
        let dir = payload?.cwd ?? cwd
        let project = URL(fileURLWithPath: dir).lastPathComponent
        let agent = source.flatMap { agentNames[$0] }
        // "Done · Codex" with the project as subtitle, or "Done · project" for other sources.
        let who = agent ?? project
        let rawEvent = payload?.event ?? event
        var kind: String?
        var derivedTitle = "Turnring"
        var derivedBody = ""
        if let rawEvent {
            guard let what = classify(rawEvent, payload) else { return nil }
            kind = what.kind
            derivedTitle = "\(what.word) · \(who)"
            derivedBody = what.body
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
        #elseif os(Linux)
        guard let name = ttyname(STDERR_FILENO) else { return nil }
        return String(cString: name)
        #else
        return nil
        #endif
    }
}
