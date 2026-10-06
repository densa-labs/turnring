import AppKit

func runAgent() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { app.run() }
}

/// The menu bar item: Pause, Recent, Preferences, Quit.
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var notifier: Notifier!
    private var server: SocketServer!
    private var recent: [(msg: Message, date: Date)] = []
    private var resumeTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        server = SocketServer(path: Prefs.socketPath) { [unowned self] msg in
            DispatchQueue.main.sync { receive(msg) }
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
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        scheduleResume()
        onboardOnFirstRun()
    }

    private func receive(_ msg: Message) -> String {
        if Prefs.isPaused { return "paused" }
        recent.insert((msg, Date()), at: 0)
        recent = Array(recent.prefix(5))
        notifier.post(msg, sound: Prefs.playSound)
        Ntfy.send(title: msg.fullTitle, message: msg.message)
        return "ok"
    }

    /// The first launch says where Turnring lives (which also triggers the permission
    /// prompt at a moment that explains it) and turns on launch at login.
    private func onboardOnFirstRun() {
        guard !Prefs.onboarded else { return }
        Prefs.onboarded = true
        if !LoginItem.managedByBrew { LoginItem.isEnabled = true }
        notifier.post(Message(title: "Turnring is running",
                              message: "It's in your menu bar. You'll get a banner here when Claude Code or Codex finishes a turn."),
                      sound: false)
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

        if Prefs.isPaused {
            let until = Prefs.pausedUntil == .distantFuture ? "" :
                " (paused until \(Prefs.pausedUntil!.formatted(date: .omitted, time: .shortened)))"
            menu.addItem(item("Resume" + until, #selector(resume)))
        } else {
            let pause = NSMenuItem(title: "Pause", action: nil, keyEquivalent: "")
            pause.submenu = NSMenu()
            pause.submenu!.addItem(item("For 15 Minutes", #selector(pause15)))
            pause.submenu!.addItem(item("For 1 Hour", #selector(pause60)))
            pause.submenu!.addItem(item("Until Resumed", #selector(pauseUntilResumed)))
            menu.addItem(pause)
        }

        let recentItem = NSMenuItem(title: "Recent", action: nil, keyEquivalent: "")
        recentItem.submenu = NSMenu()
        if recent.isEmpty {
            recentItem.submenu!.addItem(NSMenuItem(title: "Nothing yet", action: nil, keyEquivalent: ""))
        }
        let relative = RelativeDateTimeFormatter()
        for (index, entry) in recent.enumerated() {
            let when = relative.localizedString(for: entry.date, relativeTo: Date())
            // Clicking an entry brings back the app it came from, like clicking its banner.
            let row = item("\(entry.msg.fullTitle) \u{2014} \(when)", #selector(openRecent))
            row.tag = index
            if entry.msg.app == nil { row.action = nil }
            if !entry.msg.message.isEmpty { row.toolTip = entry.msg.message }
            recentItem.submenu!.addItem(row)
        }
        menu.addItem(recentItem)

        let prefs = NSMenuItem(title: "Preferences", action: nil, keyEquivalent: "")
        prefs.submenu = NSMenu()
        prefs.submenu!.addItem(item("Play Sound", #selector(toggleSound), on: Prefs.playSound))
        let login = item("Launch at Login", #selector(toggleLaunchAtLogin), on: LoginItem.isEnabled)
        if LoginItem.managedByBrew {
            login.action = nil
            login.toolTip = "Managed by Homebrew. Run `brew services stop turnring` to turn it off."
        }
        prefs.submenu!.addItem(login)
        if let topic = Prefs.ntfyTopic {
            prefs.submenu!.addItem(.separator())
            prefs.submenu!.addItem(item("Send to ntfy", #selector(toggleNtfy), on: Prefs.ntfyEnabled))
            let copy = item("Copy ntfy Topic (\(topic))", #selector(copyNtfyTopic))
            copy.toolTip = "Subscribe to this topic in the ntfy app to get pushes on your phone."
            prefs.submenu!.addItem(copy)
        }
        menu.addItem(prefs)

        menu.addItem(item("Send Test Notification", #selector(sendTest)))
        menu.addItem(.separator())
        let about = NSMenuItem(title: "Turnring \(turnringVersion)", action: nil, keyEquivalent: "")
        about.isEnabled = false
        menu.addItem(about)
        menu.addItem(item("Quit Turnring", #selector(NSApplication.terminate(_:)), key: "q", target: NSApp))
    }

    private func item(_ title: String, _ action: Selector, on: Bool? = nil, key: String = "",
                      target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target ?? self
        if let on { item.state = on ? .on : .off }
        return item
    }

    @objc private func openRecent(_ sender: NSMenuItem) {
        guard recent.indices.contains(sender.tag), let app = recent[sender.tag].msg.app else { return }
        Notifier.activate(app)
    }

    @objc private func sendTest(_ sender: Any?) {
        notifier.post(Message(title: "Turnring test", message: "Banners are working."), sound: Prefs.playSound)
    }

    @objc private func openNotificationSettings(_ sender: Any?) {
        let url = "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(Prefs.bundleID)"
        NSWorkspace.shared.open(URL(string: url)!)
    }

    @objc private func toggleSound(_ sender: Any?) { Prefs.playSound.toggle() }
    @objc private func toggleNtfy(_ sender: Any?) { Prefs.ntfyEnabled.toggle() }
    @objc private func toggleLaunchAtLogin(_ sender: Any?) { LoginItem.isEnabled.toggle() }

    @objc private func copyNtfyTopic(_ sender: Any?) {
        guard let topic = Prefs.ntfyTopic else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(topic, forType: .string)
    }
}
