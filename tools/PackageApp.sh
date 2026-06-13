#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/ClaudeDual.app"
RESOURCES="$APP/Contents/Resources"
ICON="$ROOT/Resources/ClaudeDual.icns"
ICONSET="$RESOURCES/ClaudeDual.iconset"

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

swiftc -parse-as-library \
  -module-cache-path /private/tmp/claude-dual-swift-module-cache \
  "$ROOT/ClaudeDualApp.swift" \
  -o "$APP/Contents/MacOS/ClaudeDual"

plutil -lint "$APP/Contents/Info.plist"
echo "Built $APP"
