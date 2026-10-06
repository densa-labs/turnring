import Foundation

let turnringVersion = "0.5.0"

let usage = """
usage: turnring agent
       turnring notify [--title T] [--message M] [--source NAME] [--event done|waiting] [--stdin]
       turnring setup [--remove]
       turnring ntfy [topic] [--server URL] | add <topic> | remove <topic> | list | off
       turnring history [search]
       turnring http on [--port N] | off | status
       turnring version
"""

var args = Array(CommandLine.arguments.dropFirst())
// Opened from Finder or `open`, the bundle gets no arguments (or a -psn_ one): run the agent.
if args.isEmpty || args[0].hasPrefix("-psn_") { args = ["agent"] }

switch args[0] {
case "agent":
    runAgent()
case "notify":
    NotifyCommand.run(Array(args.dropFirst()))
    exit(0)
case "setup":
    exit(SetupCommand.run(Array(args.dropFirst())))
case "history":
    let history = History()
    for entry in history.search(args.dropFirst().joined(separator: " ")).prefix(50) {
        print("\(entry.date.formatted(date: .abbreviated, time: .shortened))  \(entry.msg.fullTitle)")
        if !entry.msg.message.isEmpty { print("    " + entry.msg.message.replacingOccurrences(of: "\n", with: " ")) }
    }
case "http":
    switch args.dropFirst().first {
    case "on":
        Prefs.httpEnabled = true
        if let i = args.firstIndex(of: "--port"), i + 1 < args.count, let port = Int(args[i + 1]) { Prefs.httpPort = port }
        print("HTTP endpoint on at http://127.0.0.1:\(Prefs.httpPort)/notify (restart Turnring to apply)")
        print("Token: \(Prefs.httpToken)")
    case "off":
        Prefs.httpEnabled = false
        print("HTTP endpoint off (restart Turnring to apply)")
    default:
        print(Prefs.httpEnabled ? "on at http://127.0.0.1:\(Prefs.httpPort)/notify, token \(Prefs.httpToken)" : "off")
    }
case "ntfy":
    exit(NtfyCommand.run(Array(args.dropFirst())))
case "version", "--version":
    print("turnring \(turnringVersion)")
case "help", "--help", "-h":
    print(usage)
default:
    FileHandle.standardError.write(Data((usage + "\n").utf8))
    exit(64)
}
