# Turnring

Turnring tells you when your AI coding agent is done or needs you, so you can
stop watching the terminal. You get a notification on your Mac (and on your
phone, if you want), and clicking it takes you straight back to the agent.

Works with **Claude Code, Codex, Cursor, Gemini CLI, Antigravity, Grok Build
and Aider**. Made for macOS 14 or later; simple Windows and Linux versions too.

## Install on a Mac

It takes about a minute, and you don't need any developer tools.

1. **Open Terminal.** Press <kbd>⌘ Command</kbd> + <kbd>Space</kbd>, type
   `Terminal`, and press <kbd>Return</kbd>.
2. **Copy this line, paste it into Terminal, and press <kbd>Return</kbd>:**

   ```sh
   curl -fsSL https://raw.githubusercontent.com/densa-labs/turnring/main/install.sh | sh
   ```

3. **Click Allow** when macOS asks whether Turnring can send notifications.

That's it. A small ring icon appears in your menu bar (top right of the
screen), and Turnring connects itself to every coding agent it finds. It also
starts by itself when you log in.

**Using Codex?** The next time you start Codex, it asks whether to trust a new
hook. Choose **Trust**, or Codex can't tell Turnring when it's done.

**Check that it works:** click the ring icon and choose **Send Test
Notification**.

<details>
<summary>Prefer Homebrew?</summary>

```sh
brew tap densa-labs/turnring https://github.com/densa-labs/turnring
brew trust densa-labs/turnring
brew install turnring
brew services start turnring
```

Homebrew builds Turnring from source, which needs Apple's Command Line Tools
(`xcode-select --install`).
</details>

## Get alerts on your phone (optional)

1. Install the free **ntfy** app:
   [iPhone](https://apps.apple.com/app/ntfy/id1625396347) or
   [Android](https://play.google.com/store/apps/details?id=io.heckel.ntfy).
2. On your Mac, click the ring icon → **Preferences…** → **Phone** →
   **Set Up with ntfy**. Turnring copies a private code (your "topic").
3. In the ntfy app, tap **+**, paste the code, and tap **Subscribe**.

Keep the code to yourself: anyone who has it can read your alerts.

## What the notifications say

| You'll see | It means |
|---|---|
| **Done** · Claude Code | The agent finished. The notification shows its reply. |
| **Approve** · Codex | The agent wants to run a command, like "Run: npm test". |
| **Plan ready** · Claude Code | The agent made a plan and wants your OK. |
| **Question** · Claude Code | The agent asked you something. |
| **Waiting** · Gemini CLI | The agent is waiting for you. |
| **Limit hit** · Claude Code | You hit a usage or rate limit. |
| **Error** · Grok Build | Something went wrong. |

The project folder name appears under the title. **Click a notification** to go
back to the agent; for Terminal and iTerm2 it opens the exact tab (macOS asks
once for permission). Each notification also has **Copy Reply** and **Mute
Project for 1 Hour** buttons.

Turnring stays quiet while you're already looking at the agent.

## The menu

Click the ring icon in the menu bar:

- **Pause**: no notifications for 15 minutes, an hour, or until you resume.
- **Recent**: your last few notifications. **Show All History…** searches all
  of them.
- **Play Sound** and **Send to Phone**: quick on/off switches.
- **Send Test Notification**: checks that everything works.
- **Preferences…**: everything else, in tabs:
  - **General**: sounds, start at login, staying quiet while you watch, updates.
  - **Agents**: turn Turnring on or off for each agent.
  - **Phone**: phone alerts.
  - **Rules**: for example, "send Waiting alerts from my `prod` project to my
    phone only" or "mute Aider".
  - **Advanced**: a local web address other tools can send alerts to.

Turnring checks for updates once a day and shows a notification with an
**Update** button when there's a new version.

## Windows

1. Download `turnring-…-windows-x86_64.zip` from the
   [latest release](https://github.com/densa-labs/turnring/releases/latest).
2. Right-click the zip → **Extract All…**, and put it somewhere it can stay,
   like `C:\Users\<you>\AppData\Local\Turnring`.
3. Open that folder, click the address bar, type `powershell`, and press
   <kbd>Enter</kbd>. In the window that opens, run:

   ```powershell
   .\turnring.exe setup
   ```

Windows notifications now appear when your agents finish or need you. For
phone alerts, also run `.\turnring.exe ntfy` and subscribe to the code it
prints (see [phone alerts](#get-alerts-on-your-phone-optional)). The Windows
version has no tray icon, and clicking a notification doesn't open the agent
yet.

## Linux

Run the same line as on a Mac:

```sh
curl -fsSL https://raw.githubusercontent.com/densa-labs/turnring/main/install.sh | sh
```

It installs Turnring as a background service. Notifications use `notify-send`,
so install `libnotify-bin` (or your distribution's equivalent) if you don't
have it. There's no menu: use `turnring ntfy` for phone alerts and
`turnring history` to see past notifications.

## Uninstall

Paste the line for how you installed it:

```sh
curl -fsSL https://raw.githubusercontent.com/densa-labs/turnring/main/install.sh | sh -s -- --uninstall
```

```sh
turnring setup --remove && brew services stop turnring && brew uninstall turnring   # Homebrew
```

Both take Turnring's hooks back out of your agents' settings first.

## Something not working?

- **No notifications?** Open **System Settings → Notifications → Turnring** and
  turn on **Allow notifications**. The Turnring menu also warns you when
  they're off.
- **Nothing from Codex?** Start Codex and choose **Trust** when it asks about
  the new hook. Turnring's menu reminds you until you do.
- **Nothing from an agent you installed after Turnring?** Turnring checks for
  new agents every hour. To connect it now, open **Preferences → Agents** and
  switch it on.
- **"Turnring can't be opened" or "Apple could not verify…"?** That only
  happens if you downloaded the zip in a browser. Use the Terminal line above
  instead, or open **System Settings → Privacy & Security** and click
  **Open Anyway**. (Turnring isn't notarized by Apple, which needs a paid
  developer account.)

## For developers

<details>
<summary>Where Turnring hooks in</summary>

| Agent | File | Events |
|---|---|---|
| Claude Code | `~/.claude/settings.json` | `Stop`, `Notification`, `StopFailure` |
| Codex (CLI and app) | `~/.codex/hooks.json` | `Stop`, `PermissionRequest` |
| Cursor | `~/.cursor/hooks.json` | `stop` |
| Gemini CLI | `~/.gemini/settings.json` | `AfterAgent`, `Notification` |
| Antigravity (IDE and CLI) | `~/.gemini/config/hooks.json` | `Stop` |
| Grok Build | `~/.grok/hooks/turnring.json` | `Stop`, `Notification`, `StopFailure` |
| Aider | `~/.aider.conf.yml` | `notifications-command` |

Turnring backs up each file once as `*.turnring-backup` and keeps your other
settings, hooks and key order. It leaves a file alone if it isn't plain JSON
(for example, if it has comments) or if Aider already runs another
`notifications-command`. Grok Build also runs Claude Code's and Cursor's hooks;
Turnring ignores those copies so Grok turns aren't announced twice.

Claude Code and Grok Build report limits and errors. Codex and Gemini CLI report
approvals but have no limit event. Antigravity reports done, step limits and
errors. Cursor reports done, stopped and errors. Aider reports done.
</details>

<details>
<summary>Command line</summary>

```sh
turnring setup [--remove]          # add or remove hooks for every installed agent
turnring notify --title "Build finished" --message "All green"
turnring notify --source my-tool --event done|waiting|limit|error [--stdin]
turnring ntfy [topic] [--server URL] | add <topic> | remove <topic> | list | off
turnring history [search]
turnring http on [--port N] | off | status
turnring version
```

`turnring notify` never fails a hook: it always exits 0, gives up after 500 ms,
and prints one line to stderr if Turnring isn't running.

The local HTTP endpoint (off by default, 127.0.0.1 only) takes the same message
as JSON:

```sh
curl -X POST http://127.0.0.1:7391/notify -H "Authorization: Bearer <token>" \
  -d '{"title": "Deploy finished", "message": "v2 is live", "event": "done"}'
```

Phone pushes for approvals, plans, limits and errors go out at high priority.
Tapping a push opens the project's GitHub or GitLab page, and replies too long
for a notification come along as a `reply.txt` attachment. Each of these can be
switched off in **Preferences → Phone**.
</details>

<details>
<summary>Build from source</summary>

```sh
make test   # unit tests
make run    # build, bundle, ad-hoc sign, and open ~/Applications/Turnring.app
```

Notifications need a bundle ID, so the plain SwiftPM binary is wrapped in a
minimal `Turnring.app`. macOS ignores app bundles in temporary folders, so run
it from `~/Applications` (or wherever Homebrew puts it), not from `build/`.
</details>
