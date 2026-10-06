#!/bin/sh
# Installs Turnring from the latest GitHub release into ~/Applications and starts it at login.
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
  launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
  rm -f "$PLIST" "$LINK"
  rm -rf "$APP"
  echo "Turnring removed. Its settings stay in 'defaults read $LABEL'."
}

if [ "${1:-}" = "--uninstall" ]; then uninstall; exit 0; fi

VERSION="${TURNRING_VERSION:-$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
  | sed -n 's/.*"tag_name": *"v\{0,1\}\([^"]*\)".*/\1/p' | head -n 1)}"
[ -n "$VERSION" ] || { echo "Could not find the latest Turnring release." >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
ZIP="Turnring-$VERSION.zip"
BASE="https://github.com/$REPO/releases/download/v$VERSION"
echo "Downloading Turnring $VERSION..."
curl -fsSL -o "$TMP/$ZIP" "$BASE/$ZIP"
curl -fsSL -o "$TMP/$ZIP.sha256" "$BASE/$ZIP.sha256"
EXPECTED="$(cut -d ' ' -f 1 < "$TMP/$ZIP.sha256")"
ACTUAL="$(shasum -a 256 "$TMP/$ZIP" | cut -d ' ' -f 1)"
[ "$EXPECTED" = "$ACTUAL" ] || { echo "Checksum mismatch for $ZIP." >&2; exit 1; }

launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
mkdir -p "$HOME/Applications"
rm -rf "$APP"
ditto -x -k "$TMP/$ZIP" "$HOME/Applications"
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
codesign --force --sign - "$APP"

mkdir -p "$(dirname "$LINK")"
ln -sf "$APP/Contents/MacOS/turnring" "$LINK"

mkdir -p "$(dirname "$PLIST")"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>$APP/Contents/MacOS/turnring</string><string>agent</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><dict><key>Crashed</key><true/></dict>
  <key>ProcessType</key><string>Interactive</string>
</dict>
</plist>
EOF
launchctl bootstrap "$DOMAIN" "$PLIST"

echo "Turnring $VERSION is running in your menu bar. Allow notifications when macOS asks."
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) echo "Note: add ~/.local/bin to your PATH so hooks can find 'turnring'." ;;
esac
cat <<'EOF'

Add this to ~/.claude/settings.json to hear from Claude Code:
  "hooks": {
    "Stop":         [{ "hooks": [{ "type": "command", "command": "turnring notify --source claude-code --stdin" }] }],
    "Notification": [{ "hooks": [{ "type": "command", "command": "turnring notify --source claude-code --stdin" }] }]
  }
See the README for Codex.
EOF
