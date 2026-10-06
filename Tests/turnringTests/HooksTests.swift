import Foundation
import Testing
@testable import turnring

private func tempHome() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("turnring-hooks-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func json(_ url: URL) -> [String: Any] {
    try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
}

@Test func agentsWithoutConfigDirAreNotInstalled() {
    let hooks = Hooks(home: tempHome(), binary: "/bin/turnring")
    #expect(hooks.status(.claudeCode) == .notInstalled)
    #expect(hooks.status(.codex) == .notInstalled)
}

@Test func installKeepsOtherSettingsAndHooksAndIsIdempotent() throws {
    let home = tempHome()
    let file = home.appendingPathComponent(".claude/settings.json")
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(#"{"model":"opus","hooks":{"Stop":[{"hooks":[{"type":"command","command":"say done"}]}]}}"#.utf8).write(to: file)
    let hooks = Hooks(home: home, binary: "/opt/homebrew/bin/turnring")
    #expect(hooks.status(.claudeCode) == .off)

    #expect(try hooks.install(.claudeCode))
    #expect(hooks.status(.claudeCode) == .on)
    #expect(try hooks.install(.claudeCode) == false)

    let root = json(file)
    #expect(root["model"] as? String == "opus")
    let stop = (root["hooks"] as! [String: Any])["Stop"] as! [[String: Any]]
    #expect(stop.count == 2)
    let commands = stop.flatMap { ($0["hooks"] as! [[String: Any]]).map { $0["command"] as! String } }
    #expect(commands == ["say done", "/opt/homebrew/bin/turnring notify --source claude-code --stdin"])
    #expect(FileManager.default.fileExists(atPath: file.path + ".turnring-backup"))
}

@Test func removeTakesOutOnlyTurnringHooks() throws {
    let home = tempHome()
    let file = home.appendingPathComponent(".claude/settings.json")
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(#"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"say done"}]}]}}"#.utf8).write(to: file)
    let hooks = Hooks(home: home, binary: "/bin/turnring")
    try hooks.install(.claudeCode)
    try hooks.remove(.claudeCode)
    #expect(hooks.status(.claudeCode) == .off)
    let all = json(file)["hooks"] as! [String: Any]
    #expect(all.keys.sorted() == ["Stop"])
}

@Test func codexHooksFileIsCreated() throws {
    let home = tempHome()
    try FileManager.default.createDirectory(at: home.appendingPathComponent(".codex"), withIntermediateDirectories: true)
    let hooks = Hooks(home: home, binary: "/bin/turnring")
    #expect(hooks.status(.codex) == .off)
    try hooks.install(.codex)
    let events = (json(home.appendingPathComponent(".codex/hooks.json"))["hooks"] as! [String: Any]).keys.sorted()
    #expect(events == ["PermissionRequest", "Stop"])
    try hooks.remove(.codex)
    #expect(json(home.appendingPathComponent(".codex/hooks.json"))["hooks"] == nil)
}

@Test func filesThatAreNotPlainJSONAreLeftAlone() throws {
    let home = tempHome()
    let file = home.appendingPathComponent(".claude/settings.json")
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    let original = Data("{ // comment\n }".utf8)
    try original.write(to: file)
    #expect(throws: Hooks.HookError.self) { try Hooks(home: home, binary: "/bin/turnring").install(.claudeCode) }
    #expect(try Data(contentsOf: file) == original)
}

@Test func stablePathAvoidsTheVersionedCellar() {
    let path = Hooks.stableBinaryPath(
        executable: "/opt/homebrew/Cellar/turnring/0.3.0/Turnring.app/Contents/MacOS/turnring", home: "/nonexistent")
    #expect(path == "/opt/homebrew/bin/turnring")
}
