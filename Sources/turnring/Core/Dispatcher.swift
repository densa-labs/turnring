import Foundation

/// What a platform does with a message: show it, and say whether the user is already looking.
protocol Delivery: AnyObject {
    func showBanner(_ msg: Message)
    /// True when the agent's app is the one in front, so a banner would only interrupt.
    func isWatching(_ msg: Message) -> Bool
}

/// Decides where each message goes: pause, mutes, rules, then banner and phone.
final class Dispatcher {
    let history: History
    weak var delivery: Delivery?
    /// Called on every recorded message, for menus that show recent items.
    var onRecord: (() -> Void)?

    init(history: History = History()) {
        self.history = history
    }

    /// Returns the reply sent back to `turnring notify`: ok, paused, muted or quiet.
    func handle(_ msg: Message) -> String {
        if Prefs.isPaused { return "paused" }
        let route = Rule.route(for: msg, rules: Prefs.rules, muted: Prefs.mutedProjects)
        if route == .mute { return "muted" }
        history.add(msg)
        onRecord?()
        if Prefs.quietWhenActive, delivery?.isWatching(msg) == true { return "quiet" }
        if route.banner { delivery?.showBanner(msg) }
        if route.phone { Ntfy.send(msg) }
        return "ok"
    }
}
