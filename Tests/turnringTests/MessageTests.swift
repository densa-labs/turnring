import Foundation
import Testing
@testable import turnring

private func payload(_ json: String) -> HookPayload {
    try! JSONDecoder().decode(HookPayload.self, from: Data(json.utf8))
}

@Test func stopMapsToDone() {
    let msg = Message.make(source: "claude-code",
                           payload: payload(#"{"hook_event_name":"Stop","cwd":"/Users/me/src/turnring","last_assistant_message":"All green."}"#),
                           title: nil, message: nil, cwd: "/tmp", app: "com.apple.Terminal")
    #expect(msg.title == "Done · turnring")
    #expect(msg.message == "All green.")
    #expect(msg.event == "stop")
    #expect(msg.cwd == "/Users/me/src/turnring")
    #expect(msg.app == "com.apple.Terminal")
}

@Test func notificationAndPermissionRequestMapToWaiting() {
    let claude = Message.make(source: "claude-code",
                              payload: payload(#"{"hook_event_name":"Notification","cwd":"/a/b","message":"Claude needs your permission"}"#),
                              title: nil, message: nil, cwd: "/tmp", app: nil)
    #expect(claude.title == "Waiting · b")
    #expect(claude.message == "Claude needs your permission")
    let codex = Message.make(source: "codex", payload: payload(#"{"hook_event_name":"PermissionRequest","cwd":"/a/c"}"#),
                             title: nil, message: nil, cwd: "/tmp", app: nil)
    #expect(codex.title == "Waiting · c")
}

@Test func flagsOverridePayloadAndCwdFallsBack() {
    let msg = Message.make(source: nil, payload: payload(#"{"hook_event_name":"Stop"}"#),
                           title: "Custom", message: "Body", cwd: "/x/project", app: nil)
    #expect(msg.title == "Custom")
    #expect(msg.message == "Body")
    #expect(msg.cwd == "/x/project")
    let bare = Message.make(source: nil, payload: nil, title: nil, message: nil, cwd: "/x/project", app: nil)
    #expect(bare.title == "Turnring")
}

@Test func longBodiesAreCut() {
    let long = String(repeating: "a", count: 500)
    let msg = Message.make(source: nil, payload: nil, title: "t", message: long, cwd: "/", app: nil)
    #expect(msg.message.count == Message.bodyLimit)
    #expect(msg.message.hasSuffix("…"))
}

@Test func captureAppPrefersBundleIDThenTermProgram() {
    #expect(Message.captureApp(env: ["__CFBundleIdentifier": "com.openai.codex", "TERM_PROGRAM": "ghostty"]) == "com.openai.codex")
    #expect(Message.captureApp(env: ["__CFBundleIdentifier": Prefs.bundleID, "TERM_PROGRAM": "ghostty"]) == "com.mitchellh.ghostty")
    #expect(Message.captureApp(env: ["TERM_PROGRAM": "unknown"]) == nil)
}

@Test func sendGivesUpWhenNoAgentIsListening() {
    #expect(NotifyCommand.send(Data("{}\n".utf8), to: "/tmp/turnring-test-missing.sock", timeoutMs: 100) == nil)
}

@Test func socketRoundTrip() throws {
    let path = NSTemporaryDirectory() + "turnring-test-\(getpid()).sock"
    var received: Message?
    let server = SocketServer(path: path) { msg in received = msg; return "ok" }
    try server.start()
    let msg = Message(title: "Done · x")
    var line = try JSONEncoder().encode(msg)
    line.append(0x0A)
    #expect(NotifyCommand.send(line, to: path, timeoutMs: 500) == "ok")
    #expect(received == msg)
    #expect(NotifyCommand.send(Data("not json\n".utf8), to: path, timeoutMs: 500) == "error bad message")
}
