import Foundation

/// A per-project or per-agent rule. The first rule that matches decides where a message goes.
struct Rule: Codable, Equatable, Identifiable {
    enum Route: String, Codable, CaseIterable {
        case everywhere, bannerOnly, phoneOnly, mute

        var label: String {
            switch self {
            case .everywhere: "Banner and phone"
            case .bannerOnly: "Banner only"
            case .phoneOnly: "Phone only"
            case .mute: "Mute"
            }
        }
        var banner: Bool { self == .everywhere || self == .bannerOnly }
        var phone: Bool { self == .everywhere || self == .phoneOnly }
    }

    var id = UUID()
    /// An agent's `--source` id, or nil for any agent.
    var agent: String?
    /// Matches when the project folder name contains this text (case-insensitive). Empty matches all.
    var project: String = ""
    /// Restricts the rule to one kind: "done", "waiting", "limit" or "error". Nil matches all.
    var event: String?
    var route: Route = .everywhere

    func matches(_ msg: Message) -> Bool {
        if let agent, agent != msg.source { return false }
        if let event, event != msg.event { return false }
        if !project.isEmpty {
            guard let name = msg.project, name.localizedCaseInsensitiveContains(project) else { return false }
        }
        return true
    }

    /// The route for a message, considering muted projects first.
    static func route(for msg: Message, rules: [Rule], muted: [String: Date], now: Date = Date()) -> Route {
        if let cwd = msg.cwd, let until = muted[cwd], until > now { return .mute }
        return rules.first { $0.matches(msg) }?.route ?? .everywhere
    }
}

/// Every message Turnring delivered, newest first, kept across restarts.
final class History {
    struct Entry: Codable, Equatable {
        var msg: Message
        var date: Date
    }

    static let limit = 200
    private(set) var entries: [Entry] = []
    private let file: URL

    init(file: URL = Prefs.supportDir.appendingPathComponent("history.json")) {
        self.file = file
        if let data = try? Data(contentsOf: file),
           let saved = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = saved
        }
    }

    func add(_ msg: Message, at date: Date = Date()) {
        entries.insert(Entry(msg: msg, date: date), at: 0)
        if entries.count > History.limit { entries.removeLast(entries.count - History.limit) }
        save()
    }

    func clear() {
        entries = []
        save()
    }

    func search(_ query: String) -> [Entry] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return entries }
        return entries.filter {
            [$0.msg.fullTitle, $0.msg.fullText, $0.msg.cwd ?? ""].contains { $0.localizedCaseInsensitiveContains(q) }
        }
    }

    private func save() {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(entries).write(to: file, options: .atomic)
    }
}
