import Foundation
import Testing
@testable import turnring

private func payload(_ json: String) -> HookPayload {
    HookPayload.parse(Data(json.utf8))!
}

private func tempDir() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("turnring-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

// MARK: Messages

@Test func markdownIsStrippedFromBanners() {
    let text = Message.plainText("""
    ## Summary
    - Fixed **the bug** in `main.swift`
    * See [the PR](https://example.com/1)
    ```swift
    let x = 1
    ```
    2 * 3 is *six*
    """)
    #expect(text == "Summary\n• Fixed the bug in main.swift\n• See the PR\nlet x = 1\n2 * 3 is six")
}

@Test func longRepliesKeepTheFullTextAsDetail() {
    let long = String(repeating: "word ", count: 100)
    let msg = Message.make(source: "codex", payload: payload(#"{"hook_event_name":"Stop","cwd":"/p","last_assistant_message":"\#(long)"}"#),
                           title: nil, message: nil, cwd: "/", app: nil)!
    #expect(msg.message.count == Message.bodyLimit)
    #expect(msg.detail == long.trimmingCharacters(in: .whitespaces))
    #expect(msg.fullText == msg.detail)
}

@Test func newAgentsMapToDoneAndWaiting() {
    let gemini = Message.make(source: "gemini", payload: payload(#"{"hook_event_name":"AfterAgent","cwd":"/a/g","prompt_response":"Done it"}"#),
                              title: nil, message: nil, cwd: "/", app: nil)!
    #expect(gemini.title == "Done · Gemini CLI")
    #expect(gemini.message == "Done it")
    let cursor = Message.make(source: "cursor", payload: payload(#"{"hook_event_name":"stop","workspace_roots":["/w/site"],"status":"aborted"}"#),
                              title: nil, message: nil, cwd: "/", app: nil)!
    #expect(cursor.title == "Stopped · Cursor")
    #expect(cursor.subtitle == "site")
    let aider = Message.make(source: "aider", payload: nil, event: "done", title: nil, message: nil, cwd: "/r/app", app: nil)!
    #expect(aider.title == "Done · Aider")
    #expect(aider.subtitle == "app")
    #expect(aider.event == "done")
}

// MARK: Ordered JSON

@Test func orderedJSONKeepsKeyOrderAndValues() throws {
    let source = #"{"zeta": 1, "alpha": {"b": [true, null, 2.50], "a": "x\"y"}, "mid": "·"}"#
    var json = try JSON.parse(Data(source.utf8))
    #expect(json.keys == ["zeta", "alpha", "mid"])
    json["new"] = .string("n")
    let reparsed = try JSON.parse(json.serialized())
    #expect(reparsed.keys == ["zeta", "alpha", "mid", "new"])
    #expect(reparsed["alpha"]?.keys == ["b", "a"])
    #expect(reparsed["alpha"]?["a"]?.string == "x\"y")
    #expect(String(decoding: json.serialized(), as: UTF8.self).contains("2.50"))
    #expect(throws: JSON.ParseError.self) { try JSON.parse(Data("{ // no }".utf8)) }
}

@Test func installingHooksKeepsTheUsersKeyOrder() throws {
    let home = tempDir()
    let file = home.appendingPathComponent(".claude/settings.json")
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(#"{"theme":"dark","model":"opus","env":{"B":"1","A":"2"}}"#.utf8).write(to: file)
    try Hooks(home: home, binary: "/bin/turnring").install(.claudeCode)
    let json = try JSON.parse(Data(contentsOf: file))
    #expect(json.keys == ["theme", "model", "env", "hooks"])
    #expect(json["env"]?.keys == ["B", "A"])
}

// MARK: More agents

@Test func cursorUsesItsFlatLayout() throws {
    let home = tempDir()
    try FileManager.default.createDirectory(at: home.appendingPathComponent(".cursor"), withIntermediateDirectories: true)
    let hooks = Hooks(home: home, binary: "/bin/turnring")
    #expect(hooks.status(.cursor) == .off)
    try hooks.install(.cursor)
    #expect(hooks.status(.cursor) == .on)
    let json = try JSON.parse(Data(contentsOf: home.appendingPathComponent(".cursor/hooks.json")))
    #expect(json["version"] == .number("1"))
    #expect(json["hooks"]?["stop"]?.array?.first?["command"]?.string == "/bin/turnring notify --source cursor --stdin")
    try hooks.remove(.cursor)
    #expect(hooks.status(.cursor) == .off)
}

@Test func geminiUsesAfterAgentAndNotification() throws {
    let home = tempDir()
    try FileManager.default.createDirectory(at: home.appendingPathComponent(".gemini"), withIntermediateDirectories: true)
    try Data("{}".utf8).write(to: home.appendingPathComponent(".gemini/settings.json"))
    let hooks = Hooks(home: home, binary: "/bin/turnring")
    try hooks.install(.gemini)
    let json = try JSON.parse(Data(contentsOf: home.appendingPathComponent(".gemini/settings.json")))
    #expect(json["hooks"]?.keys == ["AfterAgent", "Notification"])
    #expect(hooks.status(.gemini) == .on)
}

@Test func aiderGetsANotificationsCommandAndGivesItBack() throws {
    let home = tempDir()
    let conf = home.appendingPathComponent(".aider.conf.yml")
    try Data("model: sonnet\n".utf8).write(to: conf)
    let hooks = Hooks(home: home, binary: "/bin/turnring", extraBinaries: [:])
    #expect(hooks.status(.aider) == .off)
    try hooks.install(.aider)
    #expect(hooks.status(.aider) == .on)
    let text = try String(contentsOf: conf, encoding: .utf8)
    #expect(text.contains("notifications: true"))
    #expect(text.contains("notifications-command: \"/bin/turnring notify --source aider --event done\""))
    try hooks.remove(.aider)
    #expect(try String(contentsOf: conf, encoding: .utf8) == "model: sonnet\n")
}

@Test func aiderWithItsOwnCommandIsLeftAlone() throws {
    let home = tempDir()
    try Data("notifications-command: say hi\n".utf8).write(to: home.appendingPathComponent(".aider.conf.yml"))
    #expect(throws: Hooks.HookError.self) { try Hooks(home: home, binary: "/bin/turnring", extraBinaries: [:]).install(.aider) }
}

@Test func codexHooksWaitForTrust() throws {
    let home = tempDir()
    try FileManager.default.createDirectory(at: home.appendingPathComponent(".codex"), withIntermediateDirectories: true)
    let hooks = Hooks(home: home, binary: "/bin/turnring")
    try hooks.install(.codex)
    #expect(hooks.status(.codex) == .untrusted)
    let path = home.appendingPathComponent(".codex/hooks.json").path
    try Data("""
    [hooks.state."\(path):stop:0:0"]
    trusted_hash = "sha256:x"

    [hooks.state."\(path):permission_request:0:0"]
    trusted_hash = "sha256:y"
    """.utf8).write(to: home.appendingPathComponent(".codex/config.toml"))
    #expect(hooks.status(.codex) == .on)
}

@Test func agentsInstalledLaterGetHookedUpUnlessTurnedOff() throws {
    let home = tempDir()
    let hooks = Hooks(home: home, binary: "/bin/turnring", extraBinaries: [:])
    #expect(hooks.installMissing(skipping: []).isEmpty)
    try FileManager.default.createDirectory(at: home.appendingPathComponent(".gemini"), withIntermediateDirectories: true)
    try Data("{}".utf8).write(to: home.appendingPathComponent(".gemini/settings.json"))
    try FileManager.default.createDirectory(at: home.appendingPathComponent(".cursor"), withIntermediateDirectories: true)
    #expect(hooks.installMissing(skipping: ["cursor"]) == [.gemini])
    #expect(hooks.status(.cursor) == .off)
}

// MARK: Rules and history

@Test func rulesRouteByAgentProjectAndEvent() {
    let msg = Message(source: "codex", event: "done", title: "Done · Codex", cwd: "/src/Website")
    let rules = [
        Rule(agent: "claude-code", route: .mute),
        Rule(agent: "codex", project: "web", event: "waiting", route: .phoneOnly),
        Rule(project: "web", route: .bannerOnly),
    ]
    #expect(Rule.route(for: msg, rules: rules, muted: [:]) == .bannerOnly)
    #expect(Rule.route(for: msg, rules: [], muted: [:]) == .everywhere)
    #expect(Rule.route(for: msg, rules: [], muted: ["/src/Website": Date().addingTimeInterval(60)]) == .mute)
    #expect(Rule.route(for: msg, rules: [], muted: ["/src/Website": Date().addingTimeInterval(-60)]) == .everywhere)
}

@Test func historySurvivesARestartAndIsSearchable() {
    let file = tempDir().appendingPathComponent("history.json")
    let history = History(file: file)
    history.add(Message(title: "Done · Codex", message: "Shipped the parser", cwd: "/src/turnring"))
    history.add(Message(title: "Waiting · Claude Code", message: "Needs permission", cwd: "/src/site"))
    let reloaded = History(file: file)
    #expect(reloaded.entries.count == 2)
    #expect(reloaded.entries.first?.msg.title == "Waiting · Claude Code")
    #expect(reloaded.search("parser").map(\.msg.title) == ["Done · Codex"])
    #expect(reloaded.search("SITE").count == 1)
}

// MARK: ntfy, HTTP, updates

@Test func repoURLsComeFromTheOriginRemote() {
    let config = """
    [core]
    \tbare = false
    [remote "upstream"]
    \turl = https://github.com/other/repo.git
    [remote "origin"]
    \turl = git@github.com:densa-labs/turnring.git
    """
    #expect(Ntfy.webURL(fromGitConfig: config) == "https://github.com/densa-labs/turnring")
    #expect(Ntfy.webURL(fromGitConfig: "[remote \"origin\"]\n url = https://user:pw@gitlab.com/a/b.git") == "https://gitlab.com/a/b")
    #expect(Ntfy.encodedHeader("Done") == "Done")
    #expect(Ntfy.encodedHeader("Done · Codex") == "=?UTF-8?B?\(Data("Done · Codex".utf8).base64EncodedString())?=")
}

#if !os(Windows)
@Test func httpEndpointNeedsTheTokenAndJSON() {
    var received: Message?
    let server = HTTPServer(port: 0, token: "t0k") { msg in received = msg; return "ok" }
    func request(_ head: String, _ body: String) -> Data { Data((head + "\r\n\r\n" + body).utf8) }
    let body = #"{"title":"Build done","message":"All green","event":"done"}"#
    #expect(server.respond(to: request("POST /notify HTTP/1.1\r\nAuthorization: Bearer nope", body)).0 == "401 Unauthorized")
    #expect(server.respond(to: request("GET / HTTP/1.1", "")).0 == "404 Not Found")
    #expect(server.respond(to: request("POST /notify HTTP/1.1\r\nAuthorization: Bearer t0k", "nope")).0 == "400 Bad Request")
    let ok = server.respond(to: request("POST /notify HTTP/1.1\r\nauthorization: Bearer t0k\r\nContent-Length: 60", body))
    #expect(ok.0 == "200 OK")
    #expect(received?.title == "Build done")
    #expect(received?.event == "done")
}
#endif

#if !os(Windows)
@Test func versionsCompareNumerically() {
    #expect(Updates.isNewer("0.10.0", than: "0.9.1"))
    #expect(!Updates.isNewer("0.4.0", than: "0.4.0"))
    #expect(Updates.isNewer("1.0", than: "0.99.9"))
    #expect(Updates.installCommand(executable: "/opt/homebrew/Cellar/turnring/0.4.0/Turnring.app/Contents/MacOS/turnring")
        .hasPrefix("/opt/homebrew/bin/brew update"))
}
#endif

// MARK: Antigravity, Grok Build and attention alerts

@Test func antigravityGetsANamedHookNextToGemini() throws {
    let home = tempDir()
    try FileManager.default.createDirectory(at: home.appendingPathComponent(".gemini/antigravity"), withIntermediateDirectories: true)
    let hooks = Hooks(home: home, binary: "/bin/turnring", extraBinaries: [:])
    #expect(hooks.status(.gemini) == .notInstalled)
    #expect(hooks.status(.antigravity) == .off)
    try hooks.install(.antigravity)
    #expect(hooks.status(.antigravity) == .on)
    let json = try JSON.parse(Data(contentsOf: home.appendingPathComponent(".gemini/config/hooks.json")))
    #expect(json["turnring"]?["Stop"]?.array?.first?["command"]?.string
        == "/bin/turnring notify --source antigravity --event done --stdin")
    try hooks.remove(.antigravity)
    #expect(hooks.status(.antigravity) == .off)
}

@Test func grokGetsItsOwnHooksFile() throws {
    let home = tempDir()
    try FileManager.default.createDirectory(at: home.appendingPathComponent(".grok"), withIntermediateDirectories: true)
    let hooks = Hooks(home: home, binary: "/bin/turnring", extraBinaries: [:])
    try hooks.install(.grok)
    #expect(hooks.status(.grok) == .on)
    let json = try JSON.parse(Data(contentsOf: home.appendingPathComponent(".grok/hooks/turnring.json")))
    #expect(json["hooks"]?.keys == ["Stop", "Notification", "StopFailure"])
}

@Test func claudeCodeGainsTheLimitsHookOnUpgrade() throws {
    let home = tempDir()
    let file = home.appendingPathComponent(".claude/settings.json")
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    let old = "/bin/turnring notify --source claude-code --stdin"
    try Data(#"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"\#(old)"}]}],"Notification":[{"hooks":[{"type":"command","command":"\#(old)"}]}]}}"#.utf8).write(to: file)
    let hooks = Hooks(home: home, binary: "/bin/turnring", extraBinaries: [:])
    #expect(hooks.status(.claudeCode) == .off)
    #expect(hooks.installMissing(skipping: []) == [.claudeCode])
    #expect(try JSON.parse(Data(contentsOf: file))["hooks"]?.keys == ["Stop", "Notification", "StopFailure"])
}

@Test func commandsWithSpacesAreQuotedAndStillRecognized() {
    let hooks = Hooks(home: tempDir(), binary: #"C:\Users\Ada Lovelace\AppData\Local\Turnring\turnring.exe"#)
    let command = hooks.command(.claudeCode)
    #expect(command.hasPrefix("\""))
    #expect(Hooks.isTurnringCommand(command))
    #expect(Hooks.isTurnringCommand("/opt/homebrew/bin/turnring notify --source codex --stdin"))
    #expect(!Hooks.isTurnringCommand("say turnring is great"))
}

@Test func attentionEventsGetTheirOwnTitles() {
    func make(_ source: String, _ json: String) -> Message? {
        Message.make(source: source, payload: payload(json), title: nil, message: nil, cwd: "/", app: nil)
    }
    let limit = make("claude-code", #"{"hook_event_name":"StopFailure","cwd":"/p/api","error":"Rate limited","error_type":"rate_limit"}"#)!
    #expect(limit.title == "Limit hit · Claude Code")
    #expect(limit.event == "limit")
    #expect(limit.needsAttention)
    let failure = make("claude-code", #"{"hook_event_name":"StopFailure","error":"Server error","error_type":"server_error"}"#)!
    #expect(failure.title == "Error · Claude Code")
    let approve = make("claude-code", #"{"hook_event_name":"Notification","notification_type":"permission_prompt","message":"Claude needs your permission to use Bash"}"#)!
    #expect(approve.title == "Approve · Claude Code")
    let plan = make("claude-code", #"{"hook_event_name":"Notification","notification_type":"permission_prompt","message":"Claude wants to exit plan mode and start on the plan"}"#)!
    #expect(plan.title == "Plan ready · Claude Code")
    let quota = make("claude-code", #"{"hook_event_name":"Notification","notification_type":"quota_auto_resume_disabled","message":"Usage limit reached"}"#)!
    #expect(quota.event == "limit")
    #expect(make("claude-code", #"{"hook_event_name":"Notification","notification_type":"auth_success"}"#) == nil)
    let codexCommand = make("codex", #"{"hook_event_name":"PermissionRequest","tool_name":"shell","tool_input":{"command":["npm","test"]}}"#)!
    #expect(codexCommand.title == "Approve · Codex")
    #expect(codexCommand.message == "Run: npm test")
    let codexPlan = make("codex", #"{"hook_event_name":"PermissionRequest","tool_name":"ExitPlanMode"}"#)!
    #expect(codexPlan.title == "Plan ready · Codex")
    let grok = make("grok", #"{"hookEventName":"StopFailure","workspaceRoot":"/w/bot","error":"Usage limit exceeded"}"#)!
    #expect(grok.title == "Limit hit · Grok Build")
    #expect(grok.subtitle == "bot")
    let agy = Message.make(source: "antigravity", payload: payload(#"{"terminationReason":"max_steps_exceeded","workspacePaths":["/w/app"]}"#),
                           event: "done", title: nil, message: nil, cwd: "/", app: nil)!
    #expect(agy.title == "Limit hit · Antigravity")
    #expect(agy.subtitle == "app")
}
