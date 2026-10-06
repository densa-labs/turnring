#if os(Windows)
import Foundation
import WinSDK

/// Windows has no menu bar agent: `turnring notify` applies pause and rules, records
/// history, shows a toast through PowerShell, and sends the ntfy push itself.
enum WindowsDelivery {
    static func deliver(_ msg: Message) {
        if Prefs.isPaused { return }
        let route = Rule.route(for: msg, rules: Prefs.rules, muted: Prefs.mutedProjects)
        if route == .mute { return }
        History().add(msg)
        if route.banner { toast(title: msg.fullTitle, body: msg.message) }
        if route.phone, Prefs.ntfyEnabled {
            // The process exits right after, so wait briefly for the push to go out.
            let done = DispatchSemaphore(value: 0)
            Ntfy.send(msg) { done.signal() }
            _ = done.wait(timeout: .now() + 5)
        }
    }

    /// A Windows toast attributed to PowerShell, which every Windows 10 and 11 install can show.
    static func toast(title: String, body: String) {
        func quoted(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "''") + "'" }
        let script = """
        [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] > $null
        $xml = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02)
        $text = $xml.GetElementsByTagName('text')
        $text.Item(0).AppendChild($xml.CreateTextNode(\(quoted(title)))) > $null
        $text.Item(1).AppendChild($xml.CreateTextNode(\(quoted(body)))) > $null
        $app = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\\WindowsPowerShell\\v1.0\\powershell.exe'
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($app).Show([Windows.UI.Notifications.ToastNotification]::new($xml))
        """
        // -EncodedCommand takes UTF-16LE base64, which sidesteps all quoting.
        var utf16 = Data()
        for unit in script.utf16 { utf16.append(contentsOf: [UInt8(unit & 0xFF), UInt8(unit >> 8)]) }
        let process = Process()
        let system = ProcessInfo.processInfo.environment["SystemRoot"] ?? "C:\\\\Windows"
        process.executableURL = URL(fileURLWithPath: system + "\\\\System32\\\\WindowsPowerShell\\\\v1.0\\\\powershell.exe")
        process.arguments = ["-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden",
                             "-EncodedCommand", utf16.base64EncodedString()]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            warn("could not show a notification: \\(error)")
        }
    }

    /// The full path of turnring.exe, for writing hooks.
    static func executablePath() -> String {
        var buffer = [WCHAR](repeating: 0, count: Int(MAX_PATH) * 4)
        let length = GetModuleFileNameW(nil, &buffer, DWORD(buffer.count))
        return String(decoding: buffer[0..<Int(length)], as: UTF16.self)
    }
}

func runAgent() {
    print("""
    On Windows there is nothing to keep running: `turnring notify` shows the notification
    and sends the ntfy push itself. Run `turnring setup` to add the agent hooks.
    """)
}
#endif
