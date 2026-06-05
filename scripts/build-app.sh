#!/usr/bin/env bash
set -euo pipefail
umask 077

APP_NAME="KyB"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/.build-app"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"

if [[ -z "$ROOT" || "$BUILD_DIR" != "$ROOT/.build-app" ]]; then
  echo "Refusing unsafe build dir: $BUILD_DIR" >&2
  exit 1
fi

rm -rf "$BUILD_DIR"
mkdir -p "$MACOS_DIR"
cp "$ROOT/Info.plist" "$APP_DIR/Contents/Info.plist"

swiftc "$ROOT"/Sources/KyB/*.swift \
  -framework SwiftUI \
  -framework AppKit \
  -framework Carbon \
  -framework CryptoKit \
  -framework ServiceManagement \
  -o "$MACOS_DIR/$APP_NAME"

chmod +x "$MACOS_DIR/$APP_NAME"

# Bundle signing binds Info.plist identifier (`local.kyb.KyB`) for TCC/Accessibility.
# Developer ID gives best stability; ad-hoc is local/dev fallback.
if command -v codesign >/dev/null 2>&1; then
  IDENTITY="${KYB_CODESIGN_IDENTITY:--}"
  codesign --force --deep --sign "$IDENTITY" "$APP_DIR" >/dev/null
  codesign --verify --deep --strict "$APP_DIR"
fi

echo "$APP_DIR"
