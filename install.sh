#!/bin/sh
# Installs Turnring from the latest GitHub release and starts it: ~/Applications on macOS,
# ~/.local/bin plus a systemd user service on Linux.
# Usage: curl -fsSL https://raw.githubusercontent.com/densa-labs/turnring/main/install.sh | sh
#        sh install.sh --uninstall
set -eu

REPO="densa-labs/turnring"
LABEL="io.github.rolling7ho.turnring"
APP="$HOME/Applications/Turnring.app"
LINK="$HOME/.local/bin/turnring"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
DOMAIN="gui/$(id -u)"

uninstall() {
  pkill -x turnring 2>/dev/null || true
  launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true # LaunchAgent from 0.1.x
  rm -f "$PLIST" "$LINK"
  rm -rf "$APP"
  echo "Turnring removed. Its settings stay in 'defaults read $LABEL'."
}

UNIT="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/turnring.service"

uninstall_linux() {
  systemctl --user disable --now turnring.service 2>/dev/null || true
  rm -f "$UNIT" "$LINK"
  echo "Turnring removed."
}

if [ "$(uname -s)" = "Linux" ] && [ "${1:-}" = "--uninstall" ]; then uninstall_linux; exit 0; fi
if [ "${1:-}" = "--uninstall" ]; then uninstall; exit 0; fi

VERSION="${TURNRING_VERSION:-$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
  | sed -n 's/.*"tag_name": *"v\{0,1\}\([^"]*\)".*/\1/p' | head -n 1)}"
[ -n "$VERSION" ] || { echo "Could not find the latest Turnring release." >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
ZIP="Turnring-$VERSION.zip"
BASE="https://github.com/$REPO/releases/download/v$VERSION"

if [ "$(uname -s)" = "Linux" ]; then
  TAR="turnring-$VERSION-linux-x86_64.tar.gz"
  echo "Downloading Turnring $VERSION for Linux..."
  curl -fsSL -o "$TMP/$TAR" "$BASE/$TAR"
  curl -fsSL -o "$TMP/$TAR.sha256" "$BASE/$TAR.sha256"
  (cd "$TMP" && sha256sum -c "$TAR.sha256" > /dev/null) || { echo "Checksum mismatch for $TAR." >&2; exit 1; }
  mkdir -p "$(dirname "$LINK")" "$(dirname "$UNIT")"
  tar -xzf "$TMP/$TAR" -C "$(dirname "$LINK")"
  cat > "$UNIT" <<EOF
[Unit]
Description=Turnring: notifications when coding agents finish

[Service]
ExecStart=$LINK agent
Restart=on-failure

[Install]
WantedBy=default.target
EOF
  systemctl --user daemon-reload
  systemctl --user enable --now turnring.service
  echo "Turnring $VERSION is running as a systemd user service. Banners use notify-send (libnotify)."
  echo "It adds hooks for Claude Code, Codex, Cursor, Gemini CLI and Aider when it starts."
  exit 0
fi
echo "Downloading Turnring $VERSION..."
curl -fsSL -o "$TMP/$ZIP" "$BASE/$ZIP"
curl -fsSL -o "$TMP/$ZIP.sha256" "$BASE/$ZIP.sha256"
EXPECTED="$(cut -d ' ' -f 1 < "$TMP/$ZIP.sha256")"
ACTUAL="$(shasum -a 256 "$TMP/$ZIP" | cut -d ' ' -f 1)"
[ "$EXPECTED" = "$ACTUAL" ] || { echo "Checksum mismatch for $ZIP." >&2; exit 1; }

pkill -x turnring 2>/dev/null || true
launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true # LaunchAgent from 0.1.x
rm -f "$PLIST"
mkdir -p "$HOME/Applications"
rm -rf "$APP"
ditto -x -k "$TMP/$ZIP" "$HOME/Applications"
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
codesign --force --sign - "$APP"

mkdir -p "$(dirname "$LINK")"
ln -sf "$APP/Contents/MacOS/turnring" "$LINK"

# The app turns on launch at login itself on first run (Preferences > Launch at Login).
open "$APP"

echo "Turnring $VERSION is running in your menu bar. Choose Allow when macOS asks about notifications."
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) echo "Note: add ~/.local/bin to your PATH to run 'turnring' from a terminal." ;;
esac
echo "It adds hooks for every agent it finds (Claude Code, Codex, Cursor, Gemini CLI, Aider)."
echo "Codex will ask you to trust the hook once."
