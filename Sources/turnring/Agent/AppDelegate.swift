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
    private var recent: [(title: String, date: Date)] = []
    private var resumeTimer: Timer?

    /// The LaunchAgent written by install.sh. Homebrew installs use `brew services` instead.
    private let launchAgentLabel = Prefs.bundleID
    private var launchAgentPlist: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(launchAgentLabel).plist")
    }

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
    }

    private func receive(_ msg: Message) -> String {
        if Prefs.isPaused { return "paused" }
        recent.insert((msg.title, Date()), at: 0)
        recent = Array(recent.prefix(5))
        notifier.post(msg, sound: Prefs.playSound)
        Ntfy.send(title: msg.title, message: msg.message)
        return "ok"
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
        let symbol = paused ? "bell.slash" : "bell"
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Turnring")
        if paused, let until = Prefs.pausedUntil, until != .distantFuture {
            resumeTimer = Timer.scheduledTimer(withTimeInterval: until.timeIntervalSinceNow + 1, repeats: false) {
                [weak self] _ in self?.scheduleResume()
            }
        }
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if Prefs.isPaused {
            let until = Prefs.pausedUntil == .distantFuture ? "" :
                " (paused until \(Prefs.pausedUntil!.formatted(date: .omitted, time: .shortened)))"
            menu.addItem(item("Resume" + until, #selector(resume)))
        } else {
            let pause = NSMenuItem(title: "Pause", action: nil, keyEquivalent: "")
            pause.submenu = NSMenu()
            pause.submenu!.addItem(item("For 15 minutes", #selector(pause15)))
            pause.submenu!.addItem(item("For 1 hour", #selector(pause60)))
            pause.submenu!.addItem(item("Until resumed", #selector(pauseUntilResumed)))
            menu.addItem(pause)
        }

        let recentItem = NSMenuItem(title: "Recent", action: nil, keyEquivalent: "")
        recentItem.submenu = NSMenu()
        if recent.isEmpty {
            recentItem.submenu!.addItem(NSMenuItem(title: "Nothing yet", action: nil, keyEquivalent: ""))
        }
        let relative = RelativeDateTimeFormatter()
        for entry in recent {
            let when = relative.localizedString(for: entry.date, relativeTo: Date())
            recentItem.submenu!.addItem(NSMenuItem(title: "\(entry.title) · \(when)", action: nil, keyEquivalent: ""))
        }
        menu.addItem(recentItem)

        let prefs = NSMenuItem(title: "Preferences", action: nil, keyEquivalent: "")
        prefs.submenu = NSMenu()
        prefs.submenu!.addItem(item("Play sound", #selector(toggleSound), on: Prefs.playSound))
        if let topic = Prefs.ntfyTopic {
            prefs.submenu!.addItem(item("Send to ntfy", #selector(toggleNtfy), on: Prefs.ntfyEnabled))
            let copy = item("ntfy topic: \(topic)", #selector(copyNtfyTopic))
            copy.toolTip = "Click to copy the topic, then subscribe to it in the ntfy app."
            prefs.submenu!.addItem(copy)
        }
        if FileManager.default.fileExists(atPath: launchAgentPlist.path) {
            prefs.submenu!.addItem(item("Launch at login", #selector(toggleLaunchAtLogin), on: launchAtLogin))
        }
        menu.addItem(prefs)

        menu.addItem(.separator())
        menu.addItem(item("Quit Turnring", #selector(NSApplication.terminate(_:)), key: "q", target: NSApp))
    }

    private func item(_ title: String, _ action: Selector, on: Bool? = nil, key: String = "",
                      target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target ?? self
        if let on { item.state = on ? .on : .off }
        return item
    }

    @objc private func toggleSound(_ sender: Any?) { Prefs.playSound.toggle() }
    @objc private func toggleNtfy(_ sender: Any?) { Prefs.ntfyEnabled.toggle() }

    @objc private func copyNtfyTopic(_ sender: Any?) {
        guard let topic = Prefs.ntfyTopic else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(topic, forType: .string)
    }

    // MARK: Launch at login (install.sh only)

    private var launchAtLogin: Bool {
        !launchctl(["print-disabled", "gui/\(getuid())"]).split(separator: "\n").contains {
            $0.contains("\"\(launchAgentLabel)\"") && ($0.contains("disabled") || $0.contains("true"))
        }
    }

    @objc private func toggleLaunchAtLogin(_ sender: Any?) {
        _ = launchctl([launchAtLogin ? "disable" : "enable", "gui/\(getuid())/\(launchAgentLabel)"])
    }

    private func launchctl(_ args: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        try? process.run()
        let out = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: out, as: UTF8.self)
    }
}
