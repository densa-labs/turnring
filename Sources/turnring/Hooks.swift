import Foundation

/// Adds and removes Turnring's hooks in Claude Code's and Codex's config files.
/// Both use the same hooks layout: {"hooks": {"<Event>": [{"hooks": [{"type": "command", "command": "…"}]}]}}.
struct Hooks {
    enum Agent: String, CaseIterable {
        case claudeCode = "claude-code", codex

        var name: String { Message.agentNames[rawValue]! }
        /// Directory that exists when the agent is installed, and the file holding its hooks.
        var configDir: String { self == .claudeCode ? ".claude" : ".codex" }
        var hooksFile: String { self == .claudeCode ? ".claude/settings.json" : ".codex/hooks.json" }
        var events: [String] { self == .claudeCode ? ["Stop", "Notification"] : ["Stop", "PermissionRequest"] }
    }

    enum Status: Equatable { case notInstalled, off, on }

    enum HookError: Error, CustomStringConvertible {
        case unreadable(String)
        var description: String {
            switch self { case .unreadable(let path): "\(path) isn't plain JSON, so Turnring left it alone" }
        }
    }

    var home: URL = FileManager.default.homeDirectoryForCurrentUser
    /// The `turnring` path written into hooks. It must survive upgrades.
    var binary: String = Hooks.stableBinaryPath()

    private func url(_ agent: Agent) -> URL { home.appendingPathComponent(agent.hooksFile) }

    func status(_ agent: Agent) -> Status {
        guard FileManager.default.fileExists(atPath: home.appendingPathComponent(agent.configDir).path) else {
            return .notInstalled
        }
        guard let root = try? read(agent) else { return .off }
        return agent.events.allSatisfy { hasTurnring(root, $0) } ? .on : .off
    }

    /// Adds the hooks that are missing. Returns false if nothing needed changing.
    @discardableResult
    func install(_ agent: Agent) throws -> Bool {
        var root = try read(agent) ?? [:]
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        var changed = false
        for event in agent.events where !hasTurnring(root, event) {
            var groups = hooks[event] as? [Any] ?? []
            groups.append(["hooks": [["type": "command", "command": command(agent)]]])
            hooks[event] = groups
            changed = true
        }
        guard changed else { return false }
        root["hooks"] = hooks
        try write(root, agent)
        return true
    }

    /// Removes every hook that runs `turnring notify`, leaving the rest of the file as it was.
    func remove(_ agent: Agent) throws {
        guard var root = try read(agent), var hooks = root["hooks"] as? [String: Any] else { return }
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            let kept = groups.compactMap { group -> [String: Any]? in
                guard let list = group["hooks"] as? [[String: Any]] else { return group }
                let rest = list.filter { !isTurnring($0) }
                if rest.isEmpty { return nil }
                var copy = group
                copy["hooks"] = rest
                return copy
            }
            if kept.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = kept }
        }
        root["hooks"] = hooks.isEmpty ? nil : hooks
        try write(root, agent)
    }

    func command(_ agent: Agent) -> String {
        "\(binary) notify --source \(agent.rawValue) --stdin"
    }

    // MARK: File access

    private func read(_ agent: Agent) throws -> [String: Any]? {
        let file = url(agent)
        guard let data = try? Data(contentsOf: file) else { return nil }
        if data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) { return [:] }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HookError.unreadable(file.path)
        }
        return root
    }

    private func write(_ root: [String: Any], _ agent: Agent) throws {
        let file = url(agent)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Keep the user's original once, next to the file.
        let backup = file.appendingPathExtension("turnring-backup")
        if FileManager.default.fileExists(atPath: file.path), !FileManager.default.fileExists(atPath: backup.path) {
            try FileManager.default.copyItem(at: file, to: backup)
        }
        var data = try JSONSerialization.data(withJSONObject: root,
                                              options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        data.append(0x0A)
        try data.write(to: file, options: .atomic)
    }

    private func hasTurnring(_ root: [String: Any], _ event: String) -> Bool {
        let groups = (root["hooks"] as? [String: Any])?[event] as? [[String: Any]] ?? []
        return groups.contains { ($0["hooks"] as? [[String: Any]] ?? []).contains(where: isTurnring) }
    }

    private func isTurnring(_ hook: [String: Any]) -> Bool {
        (hook["command"] as? String)?.contains("turnring notify") == true
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
}

/// `turnring setup` adds the hooks; `turnring setup --remove` takes them out.
enum SetupCommand {
    static func run(_ args: [String]) -> Int32 {
        let hooks = Hooks()
        let removing = args.contains("--remove")
        var failed = false
        for agent in Hooks.Agent.allCases {
            guard hooks.status(agent) != .notInstalled else {
                print("\(agent.name): not installed, skipped")
                continue
            }
            do {
                if removing {
                    try hooks.remove(agent)
                    print("\(agent.name): hooks removed")
                } else {
                    let changed = try hooks.install(agent)
                    print("\(agent.name): \(changed ? "hooks added" : "hooks already set up")")
                }
            } catch {
                warn("\(agent.name): \(error)")
                failed = true
            }
        }
        if !removing, hooks.status(.codex) == .on {
            print("Codex asks you to trust new hooks the next time it starts. Choose to trust the Turnring hook.")
        }
        return failed ? 1 : 0
    }
}
