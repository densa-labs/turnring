import Foundation
import ServiceManagement

/// Launch at login. Homebrew installs start through `brew services` instead, so the
/// setting is shown there but owned by brew.
enum LoginItem {
    static var managedByBrew: Bool {
        let service = ProcessInfo.processInfo.environment["XPC_SERVICE_NAME"] ?? ""
        return service == "sh.brew.turnring" || service == "homebrew.mxcl.turnring"
    }

    static var isEnabled: Bool {
        get { managedByBrew || SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("turnring: could not change launch at login: \(error.localizedDescription)")
            }
        }
    }
}
