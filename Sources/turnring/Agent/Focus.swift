#if os(macOS)
import AppKit

/// Brings the user back to where the agent runs: the exact Terminal or iTerm2 tab when
/// possible, the project's window in an editor, or otherwise the app itself.
enum Focus {
    static let editors: Set<String> = [
        "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.todesktop.230313mzl4w4u92", // Cursor
        "com.exafunction.windsurf", "com.vscodium",
    ]

    private static let queue = DispatchQueue(label: "turnring.focus")

    /// Runs off the main thread: the first time, macOS asks whether Turnring may control
    /// the terminal, and the menu shouldn't freeze while that question is open.
    static func bringBack(app: String?, cwd: String?, tty: String?) {
        queue.async { bringBackNow(app: app, cwd: cwd, tty: tty) }
    }

    private static func bringBackNow(app: String?, cwd: String?, tty: String?) {
        guard let app else { return }
        if Prefs.focusTab, let tty, let script = tabScript(app: app, tty: tty), run(script) { return }
        if editors.contains(app), let cwd, let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app) {
            // Opening the folder focuses the window that already has it open.
            NSWorkspace.shared.open([URL(fileURLWithPath: cwd)], withApplicationAt: appURL,
                                    configuration: NSWorkspace.OpenConfiguration())
            return
        }
        Notifier.activate(app)
    }

    /// Whether the user is looking at the agent: its app is in front and, for terminals
    /// Turnring can ask, its tab is the selected one. Call it off the main thread.
    /// It never triggers a permission prompt: until the user has allowed Turnring to
    /// control the terminal (by clicking a banner), a terminal counts as not watched.
    static func isWatching(app: String?, tty: String?) -> Bool {
        guard let app, NSWorkspace.shared.frontmostApplication?.bundleIdentifier == app else { return false }
        guard let tty, let script = selectedTTYScript(app: app) else { return true }
        guard Prefs.focusTab, mayAutomate(app) else { return false }
        var error: NSDictionary?
        guard let front = NSAppleScript(source: script)?.executeAndReturnError(&error).stringValue else { return false }
        return front == tty
    }

    /// Whether the user already lets Turnring send Apple Events to the app, without asking.
    static func mayAutomate(_ bundleID: String) -> Bool {
        var target = AEAddressDesc()
        let bytes = Array(bundleID.utf8)
        guard AECreateDesc(typeApplicationBundleID, bytes, bytes.count, &target) == noErr else { return false }
        defer { AEDisposeDesc(&target) }
        return AEDeterminePermissionToAutomateTarget(&target, typeWildCard, typeWildCard, false) == noErr
    }

    private static func tabScript(app: String, tty: String) -> String? {
        let tty = tty.replacingOccurrences(of: "\"", with: "")
        switch app {
        case "com.apple.Terminal":
            return """
            tell application "Terminal"
              repeat with w in windows
                repeat with t in tabs of w
                  if tty of t is "\(tty)" then
                    set selected tab of w to t
                    set index of w to 1
                    activate
                    return true
                  end if
                end repeat
              end repeat
            end tell
            return false
            """
        case "com.googlecode.iterm2":
            return """
            tell application "iTerm2"
              repeat with w in windows
                repeat with t in tabs of w
                  repeat with s in sessions of t
                    if tty of s is "\(tty)" then
                      select w
                      tell t to select
                      tell s to select
                      activate
                      return true
                    end if
                  end repeat
                end repeat
              end repeat
            end tell
            return false
            """
        default:
            return nil
        }
    }

    private static func selectedTTYScript(app: String) -> String? {
        switch app {
        case "com.apple.Terminal":
            "with timeout of 2 seconds\ntell application \"Terminal\" to return tty of selected tab of front window\nend timeout"
        case "com.googlecode.iterm2":
            "with timeout of 2 seconds\ntell application \"iTerm2\" to return tty of current session of current window\nend timeout"
        default:
            nil
        }
    }

    private static func run(_ source: String) -> Bool {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error { NSLog("turnring: focusing the tab failed: \(error)") }
        return result?.booleanValue == true
    }
}
#endif
