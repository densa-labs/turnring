#if os(Linux)
import Foundation

/// The Linux agent: no menu bar, banners through `notify-send` (libnotify), plus ntfy,
/// rules, history and hooks. Run it as a systemd user service (see the README).
final class LinuxAgent: Delivery {
    let dispatcher = Dispatcher()

    func showBanner(_ msg: Message) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["notify-send", "--app-name=Turnring",
                             msg.event == "waiting" ? "--urgency=critical" : "--urgency=normal",
                             msg.fullTitle, msg.message]
        try? process.run()
    }

    func isWatching(_ msg: Message) -> Bool { false }
}

func runAgent() {
    let agent = LinuxAgent()
    agent.dispatcher.delivery = agent
    let queue = DispatchQueue(label: "turnring.dispatch")
    let server = SocketServer(path: Prefs.socketPath) { msg in queue.sync { agent.dispatcher.handle(msg) } }
    do {
        try server.start()
    } catch SocketServer.StartError.alreadyRunning {
        warn("another agent is already running")
        exit(0)
    } catch {
        warn("cannot listen on \(Prefs.socketPath): \(error)")
        exit(1)
    }
    var http: HTTPServer?
    if Prefs.httpEnabled {
        http = HTTPServer(port: Prefs.httpPort, token: Prefs.httpToken) { msg in queue.sync { agent.dispatcher.handle(msg) } }
        do { try http?.start() } catch { warn("HTTP endpoint is off: \(error)") }
    }
    let added = Hooks().installMissing(skipping: Prefs.hooksOptOut)
    if !added.isEmpty { print("turnring: hooked up \(added.map(\.name).joined(separator: ", "))") }
    print("turnring: listening on \(Prefs.socketPath)")
    withExtendedLifetime((server, http)) { dispatchMain() }
}
#endif
