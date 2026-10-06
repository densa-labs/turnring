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
        #if os(macOS)
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Turnring")
        #else
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["XDG_DATA_HOME"]
            ?? NSHomeDirectory() + "/.local/share").appendingPathComponent("turnring")
        #endif
    }
    static var socketPath: String { supportDir.appendingPathComponent("turnring.sock").path }

    private static func bool(_ key: String, default value: Bool) -> Bool {
        defaults.object(forKey: key) as? Bool ?? value
    }

    // MARK: Sound

    static var playSound: Bool {
        get { bool("playSound", default: true) }
        set { defaults.set(newValue, forKey: "playSound") }
    }
    /// A sound name from /System/Library/Sounds, or "Default".
    static var doneSound: String {
        get { defaults.string(forKey: "doneSound") ?? "Default" }
        set { defaults.set(newValue, forKey: "doneSound") }
    }
    static var waitingSound: String {
        get { defaults.string(forKey: "waitingSound") ?? "Default" }
        set { defaults.set(newValue, forKey: "waitingSound") }
    }

    // MARK: Behavior

    static var pausedUntil: Date? {
        get { defaults.object(forKey: "pausedUntil") as? Date }
        set { defaults.set(newValue, forKey: "pausedUntil") }
    }
    static var isPaused: Bool { (pausedUntil ?? .distantPast) > Date() }

    /// Skip the banner and phone push while the agent's app is the one in front.
    static var quietWhenActive: Bool {
        get { bool("quietWhenActive", default: true) }
        set { defaults.set(newValue, forKey: "quietWhenActive") }
    }
    /// Bring back the exact Terminal or iTerm2 tab (needs Automation permission).
    static var focusTab: Bool {
        get { bool("focusTab", default: true) }
        set { defaults.set(newValue, forKey: "focusTab") }
    }

    /// Projects muted from a banner's "Mute for 1 Hour" action: folder path -> until.
    static var mutedProjects: [String: Date] {
        get { defaults.dictionary(forKey: "mutedProjects") as? [String: Date] ?? [:] }
        set { defaults.set(newValue.filter { $0.value > Date() }, forKey: "mutedProjects") }
    }

    static var rules: [Rule] {
        get { (defaults.data(forKey: "rules")).flatMap { try? JSONDecoder().decode([Rule].self, from: $0) } ?? [] }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: "rules") }
    }

    // MARK: Setup

    /// The last onboarding the user has seen. 1 was the 0.2 welcome; 2 adds hooks and ntfy.
    static var onboardingVersion: Int {
        get { defaults.object(forKey: "onboardingVersion") as? Int ?? (defaults.bool(forKey: "onboarded") ? 1 : 0) }
        set { defaults.set(newValue, forKey: "onboardingVersion") }
    }
    /// Agents whose hooks the user turned off, so Turnring doesn't add them back.
    static var hooksOptOut: Set<String> {
        get { Set(defaults.stringArray(forKey: "hooksOptOut") ?? []) }
        set { defaults.set(Array(newValue).sorted(), forKey: "hooksOptOut") }
    }

    // MARK: ntfy

    static var ntfyServer: String {
        get { defaults.string(forKey: "ntfyServer") ?? "https://ntfy.sh" }
        set { defaults.set(newValue, forKey: "ntfyServer") }
    }
    /// Every topic a push goes to. 0.3 stored a single `ntfyTopic`.
    static var ntfyTopics: [String] {
        get { defaults.stringArray(forKey: "ntfyTopics") ?? defaults.string(forKey: "ntfyTopic").map { [$0] } ?? [] }
        set {
            defaults.set(newValue, forKey: "ntfyTopics")
            defaults.set(newValue.first, forKey: "ntfyTopic")
        }
    }
    static var ntfyTopic: String? { ntfyTopics.first }
    static var ntfyEnabled: Bool {
        get { defaults.bool(forKey: "ntfyEnabled") }
        set { defaults.set(newValue, forKey: "ntfyEnabled") }
    }
    /// "Waiting" pushes go out at high priority so they break through on the phone.
    static var ntfyUrgentWaiting: Bool {
        get { bool("ntfyUrgentWaiting", default: true) }
        set { defaults.set(newValue, forKey: "ntfyUrgentWaiting") }
    }
    /// Tapping a push opens the project's repository page when it has one.
    static var ntfyClickRepo: Bool {
        get { bool("ntfyClickRepo", default: true) }
        set { defaults.set(newValue, forKey: "ntfyClickRepo") }
    }
    /// Long replies go along as a text attachment.
    static var ntfyAttachReply: Bool {
        get { bool("ntfyAttachReply", default: true) }
        set { defaults.set(newValue, forKey: "ntfyAttachReply") }
    }

    // MARK: HTTP endpoint

    static var httpEnabled: Bool {
        get { defaults.bool(forKey: "httpEnabled") }
        set { defaults.set(newValue, forKey: "httpEnabled") }
    }
    static var httpPort: Int {
        get { defaults.object(forKey: "httpPort") as? Int ?? 7391 }
        set { defaults.set(newValue, forKey: "httpPort") }
    }
    /// Bearer token the endpoint requires. Generated on first use.
    static var httpToken: String {
        if let token = defaults.string(forKey: "httpToken") { return token }
        let token = UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
        defaults.set(token, forKey: "httpToken")
        return token
    }

    // MARK: Updates

    static var checkForUpdates: Bool {
        get { bool("checkForUpdates", default: true) }
        set { defaults.set(newValue, forKey: "checkForUpdates") }
    }
    static var lastUpdateCheck: Date? {
        get { defaults.object(forKey: "lastUpdateCheck") as? Date }
        set { defaults.set(newValue, forKey: "lastUpdateCheck") }
    }
}
