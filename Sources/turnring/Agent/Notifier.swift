#if os(macOS)
import AppKit
import UserNotifications

/// Posts native banners and handles clicks and actions on them.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    /// Whether the user has turned Turnring's notifications off. Refreshed after each post.
    private(set) var isDenied = false
    /// Called when a banner's Update action is chosen.
    var onUpdate: (() -> Void)?

    static let messageCategory = "turnring.message"
    static let updateCategory = "turnring.update"

    override init() {
        super.init()
        center.delegate = self
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Notifier.messageCategory, actions: [
                UNNotificationAction(identifier: "copy", title: "Copy Reply"),
                UNNotificationAction(identifier: "mute", title: "Mute Project for 1 Hour"),
            ], intentIdentifiers: []),
            UNNotificationCategory(identifier: Notifier.updateCategory, actions: [
                UNNotificationAction(identifier: "update", title: "Update"),
            ], intentIdentifiers: []),
        ])
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
            self?.refreshStatus()
            if !granted {
                NSLog("turnring: notifications not allowed (\(error?.localizedDescription ?? "denied")). "
                    + "Allow Turnring in System Settings > Notifications.")
            }
        }
    }

    /// A banner for an agent message, with its sound, agent icon and actions.
    func post(_ msg: Message) {
        let content = UNMutableNotificationContent()
        content.title = msg.title
        content.body = msg.message
        if let subtitle = msg.subtitle { content.subtitle = subtitle }
        // Group a project's banners together in Notification Center.
        if let cwd = msg.cwd { content.threadIdentifier = cwd }
        if Prefs.playSound { content.sound = Sounds.notificationSound(Sounds.name(for: msg.event)) }
        var info: [String: String] = [:]
        info["app"] = msg.app
        info["cwd"] = msg.cwd
        info["tty"] = msg.tty
        info["text"] = msg.fullText
        content.userInfo = info
        if msg.event != nil { content.categoryIdentifier = Notifier.messageCategory }
        if let icon = AgentIcon.attachment(source: msg.source, app: msg.app) { content.attachments = [icon] }
        add(content)
    }

    /// A plain banner from Turnring itself (setup, tips, errors).
    func post(title: String, body: String, category: String? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if let category { content.categoryIdentifier = category }
        add(content)
    }

    private func add(_ content: UNNotificationContent) {
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)) { [weak self] error in
            if let error { NSLog("turnring: could not post notification: \(error.localizedDescription)") }
            self?.refreshStatus()
        }
    }

    func refreshStatus() {
        center.getNotificationSettings { settings in
            let denied = settings.authorizationStatus == .denied
            DispatchQueue.main.async { self.isDenied = denied }
        }
    }

    /// Brings an app forward by bundle ID.
    static func activate(_ bundleID: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    // Show banners even though Turnring is technically the active process.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler done: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo as? [String: String] ?? [:]
        DispatchQueue.main.async { [self] in
            switch response.actionIdentifier {
            case UNNotificationDefaultActionIdentifier:
                Focus.bringBack(app: info["app"], cwd: info["cwd"], tty: info["tty"])
            case "copy":
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(info["text"] ?? "", forType: .string)
            case "mute":
                if let cwd = info["cwd"] { Prefs.mutedProjects[cwd] = Date().addingTimeInterval(3600) }
            case "update":
                onUpdate?()
            default:
                break
            }
            done()
        }
    }
}

/// Notification sounds: "Default", or any sound in /System/Library/Sounds.
enum Sounds {
    static let systemDir = URL(fileURLWithPath: "/System/Library/Sounds")

    static var available: [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: systemDir.path)) ?? []
        return ["Default"] + names.filter { $0.hasSuffix(".aiff") }.map { String($0.dropLast(5)) }.sorted()
    }

    static func name(for event: String?) -> String {
        event == "done" || event == nil ? Prefs.doneSound : Prefs.waitingSound
    }

    /// Notifications can only play sounds from ~/Library/Sounds or the app bundle, so a
    /// system sound is copied to ~/Library/Sounds the first time it's used.
    static func notificationSound(_ name: String) -> UNNotificationSound {
        guard name != "Default" else { return .default }
        let fileName = "Turnring \(name).aiff"
        let target = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Sounds/\(fileName)")
        if !FileManager.default.fileExists(atPath: target.path) {
            try? FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.copyItem(at: systemDir.appendingPathComponent("\(name).aiff"), to: target)
        }
        return UNNotificationSound(named: UNNotificationSoundName(fileName))
    }

    static func preview(_ name: String) {
        if name == "Default" { NSSound.beep() } else { NSSound(named: NSSound.Name(name))?.play() }
    }
}

/// The agent's app icon, shown as a thumbnail on the banner.
enum AgentIcon {
    /// Desktop apps that stand for an agent, used when the hook ran in a terminal.
    static let agentApps = [
        "claude-code": "com.anthropic.claudefordesktop",
        "codex": "com.openai.codex",
        "cursor": "com.todesktop.230313mzl4w4u92",
    ]

    static func attachment(source: String?, app: String?) -> UNNotificationAttachment? {
        let candidates = [source.flatMap { agentApps[$0] }, app].compactMap { $0 }
        guard let bundleID = candidates.first(where: { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }),
              let png = cachedPNG(bundleID) else { return nil }
        // The system moves attachment files into its own store, so hand it a copy.
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("turnring-icon-\(UUID().uuidString).png")
        guard (try? FileManager.default.copyItem(at: png, to: copy)) != nil else { return nil }
        return try? UNNotificationAttachment(identifier: "icon", url: copy)
    }

    private static func cachedPNG(_ bundleID: String) -> URL? {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Turnring/icons")
        let file = dir.appendingPathComponent("\(bundleID).png")
        if FileManager.default.fileExists(atPath: file.path) { return file }
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 256, pixelsHigh: 256, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        icon.draw(in: NSRect(x: 0, y: 0, width: 256, height: 256))
        NSGraphicsContext.restoreGraphicsState()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = rep.representation(using: .png, properties: [:]), (try? data.write(to: file)) != nil else {
            return nil
        }
        return file
    }
}
#endif
