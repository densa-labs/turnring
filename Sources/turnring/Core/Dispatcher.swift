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

    /// Where banners and pushes run, so `turnring notify` gets its reply right away.
    private let deliver: (@escaping () -> Void) -> Void

    init(history: History = History(), deliver: @escaping (@escaping () -> Void) -> Void = { DispatchQueue.main.async(execute: $0) }) {
        self.history = history
        self.deliver = deliver
    }

    /// Returns the reply sent back to `turnring notify`: ok, paused or muted. Showing the
    /// banner (which may ask Terminal which tab is in front) happens afterwards.
    func handle(_ msg: Message) -> String {
        if Prefs.isPaused { return "paused" }
        let route = Rule.route(for: msg, rules: Prefs.rules, muted: Prefs.mutedProjects)
        if route == .mute { return "muted" }
        history.add(msg)
        onRecord?()
        deliver { [weak self] in
            guard let self else { return }
            if Prefs.quietWhenActive, delivery?.isWatching(msg) == true { return }
            if route.banner { delivery?.showBanner(msg) }
            if route.phone { Ntfy.send(msg) }
        }
        return "ok"
    }
}
