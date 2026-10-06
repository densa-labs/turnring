import AppKit
import UserNotifications

/// Posts native banners and brings the hook's app forward when one is clicked.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
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
        if sound { content.sound = .default }
        if let app = msg.app { content.userInfo = ["app": app] }
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)) { error in
            if let error { NSLog("turnring: could not post notification: \(error.localizedDescription)") }
        }
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
              let id = response.notification.request.content.userInfo["app"] as? String,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}
