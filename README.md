# Turnring

A small menu bar app that tells you when a coding agent finishes its turn or
needs you. A hook runs `turnring notify`, you get a native notification (and,
if you like, a push to your phone through [ntfy](https://ntfy.sh)), and clicking
it takes you back to the agent: the exact Terminal or iTerm2 tab, the project's
editor window, or the agent's app.

Works with Claude Code, Codex (CLI and app), Cursor, Gemini CLI and Aider.
Needs macOS 14 or later. A headless Linux build is available too.

## Install

### Homebrew (builds from source)

```sh
brew tap densa-labs/turnring https://github.com/densa-labs/turnring
brew trust densa-labs/turnring   # Homebrew asks you to trust third-party taps
brew install turnring
brew services start turnring
```

This needs a Swift toolchain; the Xcode Command Line Tools are enough
(`xcode-select --install`). `brew services` also starts Turnring at login.

### Install script (prebuilt)

```sh
curl -fsSL https://raw.githubusercontent.com/densa-labs/turnring/main/install.sh | sh
```

On macOS it installs `~/Applications/Turnring.app`, links `~/.local/bin/turnring`,
and opens Turnring, which turns on launch at login the first time it runs. On
Linux it installs `~/.local/bin/turnring` and a systemd user service.

The first time Turnring runs, it posts a banner saying what it set up, and macOS
asks whether it may send notifications. Choose **Allow**. If you missed it, turn
Turnring on in **System Settings → Notifications**.

## Hook it up

Turnring adds its hooks to every agent it finds, when it first runs and again
whenever you install another agent later:

| Agent | File | Events |
|---|---|---|
| Claude Code | `~/.claude/settings.json` | `Stop`, `Notification` |
| Codex (CLI and app) | `~/.codex/hooks.json` | `Stop`, `PermissionRequest` |
| Cursor | `~/.cursor/hooks.json` | `stop` |
| Gemini CLI | `~/.gemini/settings.json` | `AfterAgent`, `Notification` |
| Aider | `~/.aider.conf.yml` | `notifications-command` |

It backs up each file once as `*.turnring-backup`, keeps your other settings,
hooks and key order as they were, and leaves a file alone if it isn't plain JSON
(for example, if it has comments) or if Aider already runs another
`notifications-command`.

**Codex asks you to trust new hooks** the next time it starts. Choose to trust
the Turnring hook, or Codex won't run it. Until then the menu shows Codex as
"trust it in Codex". Claude Code, Cursor and Gemini CLI pick the hooks up in new
sessions.

Turn hooks on or off per agent from **Hooks** in the menu, in **Settings →
Agents**, or from a terminal. An agent you turn off stays off.

```sh
turnring setup            # add hooks for every installed agent
turnring setup --remove   # take them out again
```

### Anything else

```sh
turnring notify --title "Build finished" --message "All green"
turnring notify --source my-tool --event done      # "Done · <project>"
```

`turnring notify` never fails a hook: it always exits 0, gives up after 500 ms,
and prints one line to stderr if Turnring isn't running.

Tools that can only make HTTP requests can use the local endpoint. Turn it on
in **Settings → Advanced** (which also shows the token) or with `turnring http on`:

```sh
curl -X POST http://127.0.0.1:7391/notify -H "Authorization: Bearer <token>" \
  -d '{"title": "Deploy finished", "message": "v2 is live", "event": "done"}'
```

It listens on 127.0.0.1 only.

## Notifications

Banners are titled by agent, such as "Done · Claude Code" or "Waiting · Codex",
with the project folder underneath and the agent's app icon on the side. The
reply is shown as plain text (Markdown is stripped).

- **Click** a banner to go back. For Terminal and iTerm2, Turnring selects the
  exact tab the agent runs in; macOS asks once for permission to control that
  app. VS Code, Cursor and Windsurf open the project's window. Other apps come
  to the front.
- **Copy Reply** copies the agent's whole reply. **Mute Project for 1 Hour**
  silences that folder.
- Turnring stays quiet while you're already looking at the agent (its app is in
  front and, for Terminal and iTerm2, its tab is selected). Turn this off in
  **Settings → General**.
- Pick separate sounds for "Done" and "Waiting" in **Settings → General**.

## Menu

- **Pause** for 15 minutes, 1 hour, or until resumed. Pausing silences ntfy too,
  and the menu bar icon gets a slash.
- **Recent** lists the last 5 notifications; click one to go back.
  **Show All History…** (⌘Y) searches everything Turnring has shown, across
  restarts. `turnring history [search]` does the same in a terminal.
- **Hooks** turns each agent's hooks on or off.
- **Phone Notifications** sets up ntfy, turns it on or off, and copies topics.
- **Send Test Notification** checks that banners get through. If notifications
  are off, the menu says so and links to System Settings.
- **Settings…** (⌘,) has everything else: sounds, launch at login, quiet mode,
  tab focus, agents, phone, rules, the HTTP endpoint and update checks.

## Rules

In **Settings → Rules**, route messages by agent, project and event. The first
rule that matches wins: banner and phone, banner only, phone only, or mute. For
example, send "Waiting" from any project containing `prod` to your phone only,
or mute Aider entirely.

## Phone notifications (ntfy)

Choose **Phone Notifications → Set Up with ntfy** in the menu. Turnring creates
a private random topic and copies it; subscribe to it in the free
[ntfy app](https://ntfy.sh). From a terminal:

```sh
turnring ntfy                      # turn on with a random topic on ntfy.sh
turnring ntfy my-topic             # or pick a topic
turnring ntfy add team-topic       # send to more than one topic
turnring ntfy remove team-topic
turnring ntfy list
turnring ntfy my-topic --server https://ntfy.example.com
turnring ntfy off
```

"Waiting" pushes go out at high priority. Tapping a push opens the project's
repository page when it has a GitHub or GitLab `origin`. Replies too long for a
banner come along as a `reply.txt` attachment. Each of these can be turned off
in **Settings → Phone**.

Anyone who knows a topic on the public ntfy.sh server can read it, so prefer the
random one.

## Updates

Turnring checks GitHub once a day and posts a banner when a new version is out.
Choose **Update** on the banner (or in the menu) to install it with Homebrew or
the install script, whichever you used. Turn the check off in
**Settings → General**.

## Linux

The Linux build has no menu bar. It runs as a systemd user service, shows
banners with `notify-send` (install `libnotify-bin` or your distribution's
equivalent), and supports hooks, ntfy, rules, history and the HTTP endpoint.
Use `turnring setup`, `turnring ntfy`, `turnring http` and `turnring history`
instead of the menu. Rules can only be edited in the macOS settings window for
now. Install it with the script above, or build it:

```sh
swift build -c release
cp .build/release/turnring ~/.local/bin/
```

## Uninstall

Remove the hooks first, then the app:

```sh
turnring setup --remove
brew services stop turnring && brew uninstall turnring   # Homebrew
sh install.sh --uninstall                                 # install script
```

## Downloaded the zip by hand?

A zip downloaded in a browser is quarantined. Open Turnring once, then go to
**System Settings → Privacy & Security** and click **Open Anyway**. Homebrew and
the install script avoid this. (Turnring is ad-hoc signed, not notarized.)

## Build

```sh
make test   # unit tests
make run    # build, bundle, ad-hoc sign, and open ~/Applications/Turnring.app
```

Notifications need a bundle ID, so the plain SwiftPM binary is wrapped in a
minimal `Turnring.app`. macOS ignores bundles in temporary folders, so run it
from `~/Applications` (or wherever Homebrew puts it), not from `build/`.
