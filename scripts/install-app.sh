#!/usr/bin/env bash
set -euo pipefail
umask 077

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST_DIR="${KYB_INSTALL_DIR:-$HOME/Applications}"
APP_NAME="KyB.app"

if [[ -z "$DEST_DIR" || "$APP_NAME" != "KyB.app" || "$DEST_DIR" == "/" ]]; then
  echo "Refusing unsafe install path: $DEST_DIR/$APP_NAME" >&2
  exit 1
fi

mkdir -p "$DEST_DIR"
"$ROOT/scripts/build-app.sh" >/dev/null

# Quit old instance so TCC and LaunchServices see fresh installed bundle.
osascript -e 'tell application "KyB" to quit' >/dev/null 2>&1 || true
sleep 0.5

# Always reset Accessibility during install. Rebuilt local bundles can leave stale TCC state.
tccutil reset Accessibility local.kyb.KyB || true

# Replace app at stable path. Grant Accessibility to this installed copy, not .build-app copy.
TARGET="$DEST_DIR/$APP_NAME"
if [[ "$TARGET" != */KyB.app ]]; then
  echo "Refusing unsafe target: $TARGET" >&2
  exit 1
fi
rm -rf "$TARGET"
ditto "$ROOT/.build-app/$APP_NAME" "$TARGET"

xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null || true

open "$TARGET"
echo "$TARGET"
echo "Accessibility approval was reset for clean install. Grant Accessibility to this installed copy."
