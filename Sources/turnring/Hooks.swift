import Foundation

/// Adds and removes Turnring's hooks in each agent's config file.
///
/// Claude Code, Codex and Gemini CLI share one layout:
/// `{"hooks": {"<Event>": [{"hooks": [{"type": "command", "command": "…"}]}]}}`.
/// Cursor uses `{"version": 1, "hooks": {"<event>": [{"command": "…"}]}}`.
/// Aider has no hooks; it runs `notifications-command` from ~/.aider.conf.yml.
struct Hooks {
    enum Agent: String, CaseIterable {
        case claudeCode = "claude-code", codex, cursor, gemini, aider

        var name: String { Message.agentNames[rawValue]! }

        /// Paths (relative to home) whose presence means the agent is installed.
        var markers: [String] {
            switch self {
            case .claudeCode: [".claude"]
            case .codex: [".codex"]
            case .cursor: [".cursor"]
            case .gemini: [".gemini"]
            case .aider: [".aider.conf.yml", ".local/bin/aider"]
            }
        }

        var hooksFile: String {
            switch self {
            case .claudeCode: ".claude/settings.json"
            case .codex: ".codex/hooks.json"
            case .cursor: ".cursor/hooks.json"
            case .gemini: ".gemini/settings.json"
            case .aider: ".aider.conf.yml"
            }
        }

        var events: [String] {
            switch self {
            case .claudeCode: ["Stop", "Notification"]
            case .codex: ["Stop", "PermissionRequest"]
            case .cursor: ["stop"]
            case .gemini: ["AfterAgent", "Notification"]
            case .aider: []
            }
        }
    }

    enum Status: Equatable {
        case notInstalled, off, on
        /// Codex only: the hooks are in place but Codex hasn't been told to trust them yet.
        case untrusted
    }

    enum HookError: Error, CustomStringConvertible {
        case unreadable(String)
        case occupied(String)
        var description: String {
            switch self {
            case .unreadable(let path): "\(path) isn't plain JSON, so Turnring left it alone"
            case .occupied(let path): "\(path) already runs another notifications-command, so Turnring left it alone"
            }
        }
    }

    var home: URL = FileManager.default.homeDirectoryForCurrentUser
    /// The `turnring` path written into hooks. It must survive upgrades.
    var binary: String = Hooks.stableBinaryPath()
    /// Extra places to look for agents installed outside home (Homebrew), for detection only.
    var extraBinaries: [Agent: [String]] = [.aider: ["/opt/homebrew/bin/aider", "/usr/local/bin/aider"]]

    private func url(_ agent: Agent) -> URL { home.appendingPathComponent(agent.hooksFile) }

    func isInstalled(_ agent: Agent) -> Bool {
        let fm = FileManager.default
        return agent.markers.contains { fm.fileExists(atPath: home.appendingPathComponent($0).path) }
            || (extraBinaries[agent] ?? []).contains { fm.fileExists(atPath: $0) }
    }

    func status(_ agent: Agent) -> Status {
        guard isInstalled(agent) else { return .notInstalled }
        if agent == .aider {
            return aiderLines().contains { $0.hasPrefix("notifications-command:") && $0.contains("turnring notify") }
                ? .on : .off
        }
        guard let root = try? read(agent), agent.events.allSatisfy({ position(root, agent, $0) != nil }) else {
            return .off
        }
        if agent == .codex, !codexTrusts(root) { return .untrusted }
        return .on
    }

    /// Adds the hooks that are missing. Returns false if nothing needed changing.
    @discardableResult
    func install(_ agent: Agent) throws -> Bool {
        if agent == .aider { return try installAider() }
        var root = try read(agent) ?? .object([])
        guard root.isObject else { throw HookError.unreadable(url(agent).path) }
        var hooks = root["hooks"] ?? .object([])
        var changed = false
        for event in agent.events where position(root, agent, event) == nil {
            var groups = hooks[event]?.array ?? []
            groups.append(entry(agent))
            hooks[event] = .array(groups)
            changed = true
        }
        guard changed else { return false }
        if agent == .cursor, root["version"] == nil { root["version"] = .number("1") }
        root["hooks"] = hooks
        try write(root.serialized(), agent)
        return true
    }

    /// Removes every hook that runs `turnring notify`, leaving the rest of the file as it was.
    func remove(_ agent: Agent) throws {
        if agent == .aider { return try removeAider() }
        guard var root = try read(agent), var hooks = root["hooks"], case .object(let events) = hooks else { return }
        for member in events {
            guard let groups = member.value.array else { continue }
            var kept: [JSON] = []
            for group in groups {
                if isTurnring(group) { continue } // Cursor: the group is the hook
                if let list = group["hooks"]?.array {
                    let rest = list.filter { !isTurnring($0) }
                    if rest.isEmpty { continue }
                    var copy = group
                    copy["hooks"] = .array(rest)
                    kept.append(copy)
                } else {
                    kept.append(group)
                }
            }
            hooks[member.key] = kept.isEmpty ? nil : .array(kept)
        }
        root["hooks"] = hooks.keys.isEmpty ? nil : hooks
        try write(root.serialized(), agent)
    }

    func command(_ agent: Agent) -> String {
        agent == .aider
            ? "\(binary) notify --source aider --event done"
            : "\(binary) notify --source \(agent.rawValue) --stdin"
    }

    private func entry(_ agent: Agent) -> JSON {
        let command = JSON.string(command(agent))
        if agent == .cursor { return .object([.init(key: "command", value: command)]) }
        return .object([.init(key: "hooks", value: .array([
            .object([.init(key: "type", value: .string("command")), .init(key: "command", value: command)]),
        ]))])
    }

    /// Where Turnring's hook sits for an event: (group index, hook index).
    private func position(_ root: JSON, _ agent: Agent, _ event: String) -> (Int, Int)? {
        for (g, group) in (root["hooks"]?[event]?.array ?? []).enumerated() {
            if isTurnring(group) { return (g, 0) }
            if let h = group["hooks"]?.array?.firstIndex(where: isTurnring) { return (g, h) }
        }
        return nil
    }

    private func isTurnring(_ hook: JSON) -> Bool {
        hook["command"]?.string?.contains("turnring notify") == true
    }

    /// Codex records trusted hooks in config.toml as
    /// `[hooks.state."<hooks.json path>:<snake_event>:<group>:<hook>"]`.
    private func codexTrusts(_ root: JSON) -> Bool {
        guard let config = try? String(contentsOf: home.appendingPathComponent(".codex/config.toml"), encoding: .utf8)
        else { return false }
        let path = url(.codex).path
        return Agent.codex.events.allSatisfy { event in
            guard let (g, h) = position(root, .codex, event) else { return false }
            let snake = event.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1_$2", options: .regularExpression)
                .lowercased()
            return config.contains("[hooks.state.\"\(path):\(snake):\(g):\(h)\"]")
        }
    }

    // MARK: Aider (YAML lines)

    private static let aiderMark = " # added by Turnring"

    private func aiderLines() -> [String] {
        ((try? String(contentsOf: url(.aider), encoding: .utf8)) ?? "").components(separatedBy: "\n")
    }

    private func installAider() throws -> Bool {
        var lines = aiderLines()
        if lines.contains(where: { $0.hasPrefix("notifications-command:") }) {
            if lines.contains(where: { $0.hasPrefix("notifications-command:") && $0.contains("turnring notify") }) {
                return false
            }
            throw HookError.occupied(url(.aider).path)
        }
        while lines.last == "" { lines.removeLast() }
        if !lines.contains(where: { $0.hasPrefix("notifications:") }) {
            lines.append("notifications: true" + Hooks.aiderMark)
        }
        lines.append("notifications-command: \"\(command(.aider))\"" + Hooks.aiderMark)
        try write(Data((lines.joined(separator: "\n") + "\n").utf8), .aider)
        return true
    }

    private func removeAider() throws {
        let lines = aiderLines()
        let kept = lines.filter { !$0.hasSuffix(Hooks.aiderMark) && !$0.contains("turnring notify") }
        guard kept.count != lines.count else { return }
        try write(Data(kept.joined(separator: "\n").utf8), .aider)
    }

    // MARK: File access

    private func read(_ agent: Agent) throws -> JSON? {
        let file = url(agent)
        guard let data = try? Data(contentsOf: file) else { return nil }
        if data.allSatisfy({ [0x20, 0x0A, 0x0D, 0x09].contains($0) }) { return .object([]) }
        guard let root = try? JSON.parse(data) else { throw HookError.unreadable(file.path) }
        return root
    }

    private func write(_ data: Data, _ agent: Agent) throws {
        let file = url(agent)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Keep the user's original once, next to the file.
        let backup = file.appendingPathExtension("turnring-backup")
        if FileManager.default.fileExists(atPath: file.path), !FileManager.default.fileExists(atPath: backup.path) {
            try FileManager.default.copyItem(at: file, to: backup)
        }
        try data.write(to: file, options: .atomic)
    }

    /// Homebrew's versioned Cellar path changes on upgrade, so point at its `bin` link instead.
    /// Script installs use ~/.local/bin; anything else uses the executable itself.
    static func stableBinaryPath(executable: String = CommandLine.arguments[0],
                                 home: String = NSHomeDirectory()) -> String {
        let resolved = URL(fileURLWithPath: executable).resolvingSymlinksInPath().path
        if let range = resolved.range(of: "/Cellar/turnring/") {
            return resolved[..<range.lowerBound] + "/bin/turnring"
        }
        let local = home + "/.local/bin/turnring"
        if (try? FileManager.default.destinationOfSymbolicLink(atPath: local)) != nil { return local }
        return resolved
    }

    // MARK: Automatic setup

    /// Adds hooks for every installed agent the user hasn't turned off, including agents
    /// installed after Turnring. Returns the agents that were newly hooked up.
    @discardableResult
    func installMissing(skipping optOut: Set<String>) -> [Agent] {
        var added: [Agent] = []
        for agent in Agent.allCases where !optOut.contains(agent.rawValue) && status(agent) == .off {
            do {
                if try install(agent) { added.append(agent) }
            } catch {
                NSLog("turnring: could not add \(agent.name) hooks: \(error)")
            }
        }
        return added
    }
}

/// `turnring setup` adds the hooks; `turnring setup --remove` takes them out.
enum SetupCommand {
    static func run(_ args: [String]) -> Int32 {
        let hooks = Hooks()
        let removing = args.contains("--remove")
        var failed = false
        for agent in Hooks.Agent.allCases {
            guard hooks.isInstalled(agent) else {
                print("\(agent.name): not installed, skipped")
                continue
            }
            do {
                if removing {
                    try hooks.remove(agent)
                    Prefs.hooksOptOut.insert(agent.rawValue)
                    print("\(agent.name): hooks removed")
                } else {
                    let changed = try hooks.install(agent)
                    Prefs.hooksOptOut.remove(agent.rawValue)
                    print("\(agent.name): \(changed ? "hooks added" : "hooks already set up")")
                }
            } catch {
                warn("\(agent.name): \(error)")
                failed = true
            }
        }
        if !removing, hooks.status(.codex) == .untrusted {
            print("Codex asks you to trust new hooks the next time it starts. Choose to trust the Turnring hook.")
        }
        return failed ? 1 : 0
    }
}
