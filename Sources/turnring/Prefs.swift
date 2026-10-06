import Foundation

/// Settings shared by the agent and the CLI, stored in UserDefaults under the bundle ID.
/// Values are read at use time, so changes made by `turnring ntfy` apply on the next message.
enum Prefs {
    static let bundleID = "io.github.rolling7ho.turnring"

    static let defaults: UserDefaults = {
        // Inside the bundle the standard domain already is the bundle ID; suiteName may not equal it.
        if Bundle.main.bundleIdentifier == bundleID { return .standard }
        return UserDefaults(suiteName: bundleID)!
    }()

    static var supportDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Turnring")
    }
    static var socketPath: String { supportDir.appendingPathComponent("turnring.sock").path }

    static var playSound: Bool {
        get { defaults.object(forKey: "playSound") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "playSound") }
    }

    static var pausedUntil: Date? {
        get { defaults.object(forKey: "pausedUntil") as? Date }
        set { defaults.set(newValue, forKey: "pausedUntil") }
    }
    static var isPaused: Bool { (pausedUntil ?? .distantPast) > Date() }

    static var ntfyServer: String {
        get { defaults.string(forKey: "ntfyServer") ?? "https://ntfy.sh" }
        set { defaults.set(newValue, forKey: "ntfyServer") }
    }
    static var ntfyTopic: String? {
        get { defaults.string(forKey: "ntfyTopic") }
        set { defaults.set(newValue, forKey: "ntfyTopic") }
    }
    static var ntfyEnabled: Bool {
        get { defaults.bool(forKey: "ntfyEnabled") }
        set { defaults.set(newValue, forKey: "ntfyEnabled") }
    }
}
