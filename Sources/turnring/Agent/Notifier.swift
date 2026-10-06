import AppKit
import UserNotifications

/// Posts native banners and brings the hook's app forward when one is clicked.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    /// Whether the user has turned Turnring's notifications off. Refreshed after each post.
    private(set) var isDenied = false

    override init() {
        super.init()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
            self?.refreshStatus()
            if !granted {
                NSLog("turnring: notifications not allowed (\(error?.localizedDescription ?? "denied")). "
                    + "Allow Turnring in System Settings > Notifications.")
            }
        }
    }

    func post(_ msg: Message, sound: Bool) {
        let content = UNMutableNotificationContent()
        content.title = msg.title
        content.body = msg.message
        if let subtitle = msg.subtitle { content.subtitle = subtitle }
        // Group a project's banners together in Notification Center.
        if let cwd = msg.cwd { content.threadIdentifier = cwd }
        if sound { content.sound = .default }
        if let app = msg.app { content.userInfo = ["app": app] }
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
        defer { done() }
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              let id = response.notification.request.content.userInfo["app"] as? String else { return }
        Notifier.activate(id)
    }
}
