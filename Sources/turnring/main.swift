import Foundation

let turnringVersion = "0.3.0"

let usage = """
usage: turnring agent
       turnring notify [--title T] [--message M] [--source NAME] [--stdin]
       turnring setup [--remove]
       turnring ntfy [topic] [--server URL] | turnring ntfy off
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
