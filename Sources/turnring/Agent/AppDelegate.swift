#if os(macOS)
import AppKit
import SwiftUI

func runAgent() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { app.run() }
}

/// The menu bar item and everything the running agent owns.
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, Delivery {
    private var statusItem: NSStatusItem!
    private var notifier: Notifier!
    private var server: SocketServer!
    private var http: HTTPServer?
    private let dispatcher = Dispatcher()
    private let hooks = Hooks()
    private let windows = WindowPresenter()
    private var resumeTimer: Timer?
    private var hourly: Timer?
    private var availableUpdate: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        server = SocketServer(path: Prefs.socketPath) { [unowned self] msg in
            DispatchQueue.main.sync { dispatcher.handle(msg) }
        }
        do {
            try server.start()
        } catch SocketServer.StartError.alreadyRunning {
            NSLog("turnring: another agent is already running")
            exit(0)
        } catch {
            NSLog("turnring: cannot listen on \(Prefs.socketPath): \(error)")
            exit(1)
        }
        notifier = Notifier()
        notifier.onUpdate = { [unowned self] in installUpdate() }
        dispatcher.delivery = self
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        scheduleResume()
        onboardOnFirstRun()
        restartHTTP()
        NotificationCenter.default.addObserver(forName: .turnringSettingsChanged, object: nil, queue: .main) {
            [unowned self] _ in restartHTTP()
        }
        // Hook up agents installed later, and look for updates, once an hour.
        hourly = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [unowned self] _ in hourlyChecks() }
        hourlyChecks()
    }

    // MARK: Delivery

    func showBanner(_ msg: Message) { notifier.post(msg) }

    func isWatching(_ msg: Message) -> Bool { Focus.isWatching(app: msg.app, tty: msg.tty) }

    // MARK: Setup

    /// First run: turn on launch at login, add the agent hooks, and say what happened.
    /// The first banner also brings up the notification permission prompt at a moment
    /// that explains it. Users of 0.2 get the hooks and ntfy part once.
    private func onboardOnFirstRun() {
        let seen = Prefs.onboardingVersion
        guard seen < 2 else { return }
        Prefs.onboardingVersion = 2
        if seen == 0, !LoginItem.managedByBrew { LoginItem.isEnabled = true }

        hooks.installMissing(skipping: Prefs.hooksOptOut)
        let on = Hooks.Agent.allCases.filter { [.on, .untrusted].contains(hooks.status($0)) }
        let body: String
        if on.isEmpty {
            body = "Install Claude Code, Codex, Cursor, Gemini CLI or Aider. Turnring hooks it up when it appears."
        } else {
            body = Self.list(on.map(\.name)) + " will tell you here when a turn ends."
                + (on.contains(.codex) ? " Codex asks you to trust the Turnring hook once. Choose Trust." : "")
        }
        notifier.post(title: "Turnring is set up", body: body)
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [self] in
            notifier.post(title: "Want these on your phone too?",
                          body: "Open Turnring Preferences > Phone to send them through the free ntfy app.")
        }
    }

    private func hourlyChecks() {
        let added = hooks.installMissing(skipping: Prefs.hooksOptOut)
        if !added.isEmpty {
            let trust = added.contains(.codex) ? " Codex asks you to trust the Turnring hook once. Choose Trust." : ""
            notifier.post(title: "Turnring hooked up \(Self.list(added.map(\.name)))",
                          body: "New sessions will notify you here. Turn it off in Turnring Preferences > Agents." + trust)
        }
        guard Prefs.checkForUpdates else { return }
        Updates.check { [weak self] version in
            guard let self, let version else { return }
            DispatchQueue.main.async {
                guard self.availableUpdate != version else { return }
                self.availableUpdate = version
                self.notifier.post(title: "Turnring \(version) is available",
                                   body: "You have \(turnringVersion). Choose Update to install it.",
                                   category: Notifier.updateCategory)
            }
        }
    }

    private func installUpdate() {
        let command = Updates.installCommand()
        notifier.post(title: "Updating Turnring", body: "Turnring restarts when the update is installed.")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        process.terminationHandler = { [weak self] p in
            guard p.terminationStatus != 0 else { return }
            DispatchQueue.main.async {
                self?.notifier.post(title: "Turnring couldn't update", body: "Run this in a terminal: \(command)")
            }
        }
        try? process.run()
    }

    private func restartHTTP() {
        http?.stop()
        http = nil
        guard Prefs.httpEnabled else { return }
        let server = HTTPServer(port: Prefs.httpPort, token: Prefs.httpToken) { [unowned self] msg in
            DispatchQueue.main.sync { dispatcher.handle(msg) }
        }
        do {
            try server.start()
            http = server
        } catch {
            notifier.post(title: "Turnring's HTTP endpoint is off", body: "\(error)")
        }
    }

    static func list(_ names: [String]) -> String {
        names.count <= 1 ? names.joined()
            : names.dropLast().joined(separator: ", ") + " and " + names.last!
    }

    // MARK: Pause

    private func pause(for seconds: TimeInterval?) {
        Prefs.pausedUntil = seconds.map { Date().addingTimeInterval($0) } ?? .distantFuture
        scheduleResume()
    }

    @objc private func pause15(_ sender: Any?) { pause(for: 15 * 60) }
    @objc private func pause60(_ sender: Any?) { pause(for: 60 * 60) }
    @objc private func pauseUntilResumed(_ sender: Any?) { pause(for: nil) }
    @objc private func resume(_ sender: Any?) {
        Prefs.pausedUntil = nil
        scheduleResume()
    }

    /// Updates the icon now and again when a timed pause runs out.
    private func scheduleResume() {
        resumeTimer?.invalidate()
        let paused = Prefs.isPaused
        let button = statusItem.button
        button?.image = Icons.menuBar(paused: paused)
        button?.toolTip = paused ? "Turnring (paused)" : "Turnring"
        button?.setAccessibilityLabel(paused ? "Turnring, paused" : "Turnring")
        if paused, let until = Prefs.pausedUntil, until != .distantFuture {
            resumeTimer = Timer.scheduledTimer(withTimeInterval: until.timeIntervalSinceNow + 1, repeats: false) {
                [weak self] _ in self?.scheduleResume()
            }
        }
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        notifier.refreshStatus() // picks up a change in System Settings by the next open

        if notifier.isDenied {
            menu.addItem(item("Notifications are off. Turn them on\u{2026}", #selector(openNotificationSettings)))
            menu.addItem(.separator())
        }
        if let version = availableUpdate {
            menu.addItem(item("Update to Turnring \(version)\u{2026}", #selector(updateNow)))
            menu.addItem(.separator())
        }

        if Prefs.isPaused {
            let until = Prefs.pausedUntil == .distantFuture ? "" :
                " (paused until \(Prefs.pausedUntil!.formatted(date: .omitted, time: .shortened)))"
            menu.addItem(item("Resume" + until, #selector(resume)))
        } else {
            let pause = submenu("Pause")
            pause.submenu!.addItem(item("For 15 Minutes", #selector(pause15)))
            pause.submenu!.addItem(item("For 1 Hour", #selector(pause60)))
            pause.submenu!.addItem(item("Until Resumed", #selector(pauseUntilResumed)))
            menu.addItem(pause)
        }

        let recent = submenu("Recent")
        let entries = dispatcher.history.entries.prefix(5)
        if entries.isEmpty {
            recent.submenu!.addItem(NSMenuItem(title: "Nothing yet", action: nil, keyEquivalent: ""))
        }
        let relative = RelativeDateTimeFormatter()
        for (index, entry) in entries.enumerated() {
            let when = relative.localizedString(for: entry.date, relativeTo: Date())
            // Clicking an entry brings back where it came from, like clicking its banner.
            let row = item("\(entry.msg.fullTitle) \u{2014} \(when)", #selector(openRecent))
            row.tag = index
            if entry.msg.app == nil { row.action = nil }
            if !entry.msg.message.isEmpty { row.toolTip = entry.msg.message }
            recent.submenu!.addItem(row)
        }
        recent.submenu!.addItem(.separator())
        recent.submenu!.addItem(item("Show All History\u{2026}", #selector(showHistory), key: "y"))
        menu.addItem(recent)

        // Everyday switches live here; everything else is in Preferences.
        menu.addItem(.separator())
        menu.addItem(item("Play Sound", #selector(toggleSound), on: Prefs.playSound))
        if !Prefs.ntfyTopics.isEmpty {
            menu.addItem(item("Send to Phone", #selector(toggleNtfy), on: Prefs.ntfyEnabled))
        }
        if hooks.status(.codex) == .untrusted {
            let codex = item("Codex: Trust the Turnring Hook\u{2026}", #selector(showAgents))
            codex.toolTip = "Start Codex and choose to trust the Turnring hook, or Codex won't run it."
            menu.addItem(codex)
        }
        menu.addItem(.separator())
        menu.addItem(item("Send Test Notification", #selector(sendTest)))
        menu.addItem(item("Preferences\u{2026}", #selector(showPreferences), key: ","))
        menu.addItem(.separator())
        let about = NSMenuItem(title: "Turnring \(turnringVersion)", action: nil, keyEquivalent: "")
        about.isEnabled = false
        menu.addItem(about)
        menu.addItem(item("Quit Turnring", #selector(NSApplication.terminate(_:)), key: "q", target: NSApp))
    }

    private func submenu(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = NSMenu()
        return item
    }

    private func item(_ title: String, _ action: Selector, on: Bool? = nil, key: String = "",
                      target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target ?? self
        if let on { item.state = on ? .on : .off }
        return item
    }

    // MARK: Actions

    @objc private func openRecent(_ sender: NSMenuItem) {
        let entries = dispatcher.history.entries
        guard entries.indices.contains(sender.tag) else { return }
        let msg = entries[sender.tag].msg
        Focus.bringBack(app: msg.app, cwd: msg.cwd, tty: msg.tty)
    }

    @objc private func showHistory(_ sender: Any?) {
        windows.show("history", title: "Turnring History", view: HistoryView(model: HistoryModel(history: dispatcher.history)))
    }

    @objc private func showPreferences(_ sender: Any?) { windows.showPreferences() }
    @objc private func showAgents(_ sender: Any?) { windows.showPreferences(.agents) }
    @objc private func toggleSound(_ sender: Any?) { Prefs.playSound.toggle() }

    @objc private func sendTest(_ sender: Any?) {
        notifier.post(Message(source: nil, event: "done", title: "Turnring test", message: "Banners are working."))
    }

    @objc private func updateNow(_ sender: Any?) { installUpdate() }

    @objc private func openNotificationSettings(_ sender: Any?) {
        let url = "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(Prefs.bundleID)"
        NSWorkspace.shared.open(URL(string: url)!)
    }

    @objc private func toggleNtfy(_ sender: Any?) { Prefs.ntfyEnabled.toggle() }
}
#endif
