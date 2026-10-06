import Foundation

/// One notification request, sent from `turnring notify` to the agent as a JSON line.
struct Message: Codable, Equatable {
    var v = 1
    var source: String?
    var event: String?
    var title: String
    var subtitle: String?
    var message: String = ""
    var cwd: String?
    var app: String?
    var ts: String?
}

/// Fields Turnring reads from a Claude Code or Codex hook payload (stdin JSON).
/// Both agents use the same names.
struct HookPayload: Decodable {
    var hook_event_name: String?
    var cwd: String?
    var message: String?
    var last_assistant_message: String?
}

extension Message {
    static let bodyLimit = 200

    /// Display names for `--source`. Titles name the agent; the project goes in the subtitle.
    static let agentNames = ["claude-code": "Claude Code", "codex": "Codex"]

    /// Title and subtitle on one line, for ntfy and the Recent menu.
    var fullTitle: String { subtitle.map { "\(title) · \($0)" } ?? title }

    /// Builds the message from a hook payload. Explicit `--title`/`--message` win.
    static func make(source: String?, payload: HookPayload?, title: String?, message: String?,
                     cwd: String, app: String?, now: Date = Date()) -> Message {
        let dir = payload?.cwd ?? cwd
        let project = URL(fileURLWithPath: dir).lastPathComponent
        let agent = source.flatMap { agentNames[$0] }
        // "Done · Codex" with the project as subtitle, or "Done · project" for other sources.
        let who = agent ?? project
        var derivedTitle = "Turnring"
        var derivedBody = ""
        if let event = payload?.hook_event_name {
            switch event {
            case "Stop":
                derivedTitle = "Done · \(who)"
                derivedBody = payload?.last_assistant_message ?? ""
            case "Notification", "PermissionRequest":
                derivedTitle = "Waiting · \(who)"
                derivedBody = payload?.message ?? ""
            default:
                derivedTitle = "\(event) · \(who)"
            }
        }
        let body = (message ?? derivedBody).trimmingCharacters(in: .whitespacesAndNewlines)
        return Message(
            source: source,
            event: payload?.hook_event_name?.lowercased(),
            title: title ?? derivedTitle,
            subtitle: title == nil && agent != nil && payload?.hook_event_name != nil ? project : nil,
            message: body.count > bodyLimit ? String(body.prefix(bodyLimit - 1)) + "…" : body,
            cwd: dir,
            app: app,
            ts: ISO8601DateFormatter().string(from: now)
        )
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
}
