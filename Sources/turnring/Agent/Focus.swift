#if os(macOS)
import AppKit

/// Brings the user back to where the agent runs: the exact Terminal or iTerm2 tab when
/// possible, the project's window in an editor, or otherwise the app itself.
enum Focus {
    static let editors: Set<String> = [
        "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.todesktop.230313mzl4w4u92", // Cursor
        "com.exafunction.windsurf", "com.vscodium",
    ]

    static func bringBack(app: String?, cwd: String?, tty: String?) {
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
    /// Turnring can ask, its tab is the selected one.
    static func isWatching(app: String?, tty: String?) -> Bool {
        guard let app, NSWorkspace.shared.frontmostApplication?.bundleIdentifier == app else { return false }
        guard Prefs.focusTab, let tty, let script = selectedTTYScript(app: app) else { return true }
        var error: NSDictionary?
        guard let front = NSAppleScript(source: script)?.executeAndReturnError(&error).stringValue else { return true }
        return front == tty
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
            "tell application \"Terminal\" to return tty of selected tab of front window"
        case "com.googlecode.iterm2":
            "tell application \"iTerm2\" to return tty of current session of current window"
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
