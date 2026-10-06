# Turnring

A small macOS menu bar app that tells you when a coding agent finishes its turn.
A hook runs `turnring notify`, you get one native notification (and optionally a
push to your phone through [ntfy](https://ntfy.sh)), and clicking it brings the
agent's app back to the front.

Works with Claude Code and Codex (CLI and app). Needs macOS 14 or later.

## Install

### Homebrew (builds from source)

```sh
brew tap densa-labs/turnring https://github.com/densa-labs/turnring
brew install turnring
brew services start turnring
```

This needs a Swift toolchain; the Xcode Command Line Tools are enough
(`xcode-select --install`). `brew services` also starts Turnring at login.

### Install script (prebuilt)

```sh
curl -fsSL https://raw.githubusercontent.com/densa-labs/turnring/main/install.sh | sh
```

It installs `~/Applications/Turnring.app`, links `~/.local/bin/turnring`, and
adds a LaunchAgent so Turnring starts at login. Remove it with
`sh install.sh --uninstall`.

The first time Turnring runs, macOS asks whether it may send notifications.
Choose **Allow**. If you missed it, turn Turnring on in **System Settings →
Notifications**.

## Hook it up

Apps started from the Dock (the Claude and Codex desktop apps) don't see your
shell's PATH, so use the full path to `turnring` in hooks: `/opt/homebrew/bin/turnring`
for Homebrew, `~/.local/bin/turnring` for the install script.

### Claude Code

Add to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "Stop":         [{ "hooks": [{ "type": "command", "command": "turnring notify --source claude-code --stdin" }] }],
    "Notification": [{ "hooks": [{ "type": "command", "command": "turnring notify --source claude-code --stdin" }] }]
  }
}
```

`Stop` gives you "Done · <project>". `Notification` gives you
"Waiting · <project>" when Claude needs your input.

### Codex

Add to `~/.codex/hooks.json` (shared by the Codex CLI and app):

```json
{
  "hooks": {
    "Stop":              [{ "hooks": [{ "type": "command", "command": "turnring notify --source codex --stdin" }] }],
    "PermissionRequest": [{ "hooks": [{ "type": "command", "command": "turnring notify --source codex --stdin" }] }]
  }
}
```

Codex asks you to trust new hooks before it runs them. Turnring uses hooks
rather than Codex's `notify` setting, so it doesn't replace anything you already
run from `notify`.

### Anything else

```sh
turnring notify --title "Build finished" --message "All green"
```

`turnring notify` never fails a hook: it always exits 0, gives up after 500 ms,
and prints one line to stderr if Turnring isn't running.

## Menu

- **Pause** for 15 minutes, 1 hour, or until resumed. Pausing silences ntfy too.
- **Recent** shows the last 5 notifications since Turnring started.
- **Preferences**: play sound, send to ntfy and the ntfy topic (click it to copy;
  both appear once a topic is set), and launch at login (install script only; Homebrew uses `brew services`).

## ntfy

```sh
turnring ntfy                      # turn on with a random topic on ntfy.sh
turnring ntfy my-topic             # or pick a topic
turnring ntfy my-topic --server https://ntfy.example.com
turnring ntfy off
```

Subscribe to the printed topic in the ntfy app. Anyone who knows a topic on the
public ntfy.sh server can read it, so prefer the random one.

## Downloaded the zip by hand?

A zip downloaded in a browser is quarantined. Open Turnring once, then go to
**System Settings → Privacy & Security** and click **Open Anyway**. Homebrew and
the install script avoid this.

## Build

```sh
make test   # unit tests
make run    # build, bundle, ad-hoc sign, and open ~/Applications/Turnring.app
```

Notifications need a bundle ID, so the plain SwiftPM binary is wrapped in a
minimal `Turnring.app`. macOS ignores bundles in temporary folders, so run it
from `~/Applications` (or wherever Homebrew puts it), not from `build/`.
