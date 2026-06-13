#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/ClaudeDual.app"
RESOURCES="$APP/Contents/Resources"
ICON="$ROOT/Resources/ClaudeDual.icns"
ICONSET="$RESOURCES/ClaudeDual.iconset"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$RESOURCES"

cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

if [[ ! -f "$ICON" ]]; then
  echo "Resources/ClaudeDual.icns missing; generating it once from Resources/icon.png"
  mkdir -p "$ICONSET"
  sips -z 16 16 "$ROOT/Resources/icon.png" --out "$ICONSET/icon_16x16.png" >/dev/null
  sips -z 32 32 "$ROOT/Resources/icon.png" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
  sips -z 32 32 "$ROOT/Resources/icon.png" --out "$ICONSET/icon_32x32.png" >/dev/null
  sips -z 64 64 "$ROOT/Resources/icon.png" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
  sips -z 128 128 "$ROOT/Resources/icon.png" --out "$ICONSET/icon_128x128.png" >/dev/null
  sips -z 256 256 "$ROOT/Resources/icon.png" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
  sips -z 256 256 "$ROOT/Resources/icon.png" --out "$ICONSET/icon_256x256.png" >/dev/null
  sips -z 512 512 "$ROOT/Resources/icon.png" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
  sips -z 512 512 "$ROOT/Resources/icon.png" --out "$ICONSET/icon_512x512.png" >/dev/null
  sips -z 1024 1024 "$ROOT/Resources/icon.png" --out "$ICONSET/icon_512x512@2x.png" >/dev/null
  python3 "$ROOT/tools/BuildIcns.py" "$ICONSET" "$ICON"
fi

cp "$ICON" "$RESOURCES/ClaudeDual.icns"
cp "$ROOT/Resources/proxy_server.py" "$RESOURCES/proxy_server.py"

BIN="$APP/Contents/MacOS/ClaudeDual"
CACHE="/private/tmp/claude-dual-swift-module-cache"
DEPLOY_TARGET="13.0"

if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  # Build a universal binary so both Apple Silicon and Intel Macs can run it.
  swiftc -parse-as-library -module-cache-path "$CACHE" \
    -target "arm64-apple-macos$DEPLOY_TARGET" \
    "$ROOT/ClaudeDualApp.swift" -o "$BIN.arm64"
  swiftc -parse-as-library -module-cache-path "$CACHE" \
    -target "x86_64-apple-macos$DEPLOY_TARGET" \
    "$ROOT/ClaudeDualApp.swift" -o "$BIN.x86_64"
  lipo -create "$BIN.arm64" "$BIN.x86_64" -output "$BIN"
  rm -f "$BIN.arm64" "$BIN.x86_64"
else
  swiftc -parse-as-library -module-cache-path "$CACHE" \
    "$ROOT/ClaudeDualApp.swift" -o "$BIN"
fi

plutil -lint "$APP/Contents/Info.plist"
echo "Built $APP"
lipo -info "$BIN" 2>/dev/null || true
