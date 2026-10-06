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
opens Turnring, which turns on launch at login the first time it runs. Remove it with
`sh install.sh --uninstall`.

The first time Turnring runs, it posts a banner saying what it set up, and macOS
asks whether it may send notifications.
Choose **Allow**. If you missed it, turn Turnring on in **System Settings →
Notifications**.

## Hook it up

The first time Turnring runs, it adds its hooks to every agent it finds:
`~/.claude/settings.json` for Claude Code and `~/.codex/hooks.json` for Codex
(CLI and app). It backs up each file once as `*.turnring-backup` and leaves your
other settings and hooks alone. A banner tells you what it set up.

**Codex asks you to trust new hooks** the next time it starts. Choose to trust
the Turnring hook, or Codex won't run it. Claude Code picks the hooks up in new
sessions.

Turn hooks on or off per agent from **Hooks** in the menu, or from a terminal:

```sh
turnring setup            # add hooks for every installed agent
turnring setup --remove   # take them out again
```

Turnring leaves a config file alone if it isn't plain JSON (for example, if it
has comments). In that case, add the hook by hand:

```json
{
  "hooks": {
    "Stop":         [{ "hooks": [{ "type": "command", "command": "/opt/homebrew/bin/turnring notify --source claude-code --stdin" }] }],
    "Notification": [{ "hooks": [{ "type": "command", "command": "/opt/homebrew/bin/turnring notify --source claude-code --stdin" }] }]
  }
}
```

For Codex, use `--source codex` with the `Stop` and `PermissionRequest` events.
Use the full path to `turnring` (`~/.local/bin/turnring` for the install
script), because the Claude and Codex desktop apps don't see your shell's PATH.

### Anything else

```sh
turnring notify --title "Build finished" --message "All green"
```

`turnring notify` never fails a hook: it always exits 0, gives up after 500 ms,
and prints one line to stderr if Turnring isn't running.

## Menu

- **Pause** for 15 minutes, 1 hour, or until resumed. Pausing silences ntfy too,
  and the menu bar icon gets a slash.
- **Recent** lists the last 5 notifications since Turnring started. Click one to
  bring its app forward again.
- **Hooks** turns the Claude Code and Codex hooks on or off.
- **Preferences**: play sound and launch at login. With Homebrew, launch at
  login belongs to `brew services`.
- **Phone Notifications** sets up ntfy, turns it on or off, and copies your topic.
- **Send Test Notification** checks that banners get through. If notifications
  are off, the menu says so and links to System Settings.

Banners are titled by agent, such as "Done · Claude Code" or "Waiting · Codex",
with the project folder underneath. Clicking one brings back the app the agent
runs in. macOS shows that app's last-used window; Turnring doesn't pick a
specific terminal tab.

## Phone notifications (ntfy)

Choose **Phone Notifications → Set Up with ntfy** in the menu. Turnring creates
a private random topic and copies it; subscribe to it in the free
[ntfy app](https://ntfy.sh). From a terminal:

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
