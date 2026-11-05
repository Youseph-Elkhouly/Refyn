#!/bin/sh
# Builds Refyn.app: the Swift app, plus the Node helper (compiled, with production dependencies) in Resources.
# Usage: Scripts/build-app.sh [debug|release]   (default: release)
set -eu

CONFIG=${1:-release}
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BUILD_DIR="$ROOT_DIR/.build/$CONFIG"
APP_DIR="$ROOT_DIR/.build/Refyn.app"
RES_DIR="$APP_DIR/Contents/Resources"

cd "$ROOT_DIR"
command -v node >/dev/null || { echo "Node.js 20+ is required to build the helper" >&2; exit 1; }

echo "› Building helper"
(cd RefineHelper && npm ci --no-audit --no-fund && npm run build)

echo "› Building app ($CONFIG)"
swift build -c "$CONFIG"
echo "› Building MLX Metal kernels"
"$ROOT_DIR/Scripts/build-mlx-metallib.sh" "$ROOT_DIR/.build/$CONFIG"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$RES_DIR/RefineHelper"
cp "$BUILD_DIR/Refyn" "$APP_DIR/Contents/MacOS/Refyn"
cp "$BUILD_DIR/mlx.metallib" "$APP_DIR/Contents/MacOS/mlx.metallib"
# SwiftPM resource bundles (GRDB, WhisperKit dependencies).
for bundle in "$BUILD_DIR"/*.bundle; do
  [ -e "$bundle" ] && cp -R "$bundle" "$RES_DIR/"
done

echo "› Bundling helper"
cp -R RefineHelper/dist RefineHelper/package.json RefineHelper/package-lock.json "$RES_DIR/RefineHelper/"
rm -rf "$RES_DIR/RefineHelper/dist/test"
(cd "$RES_DIR/RefineHelper" && npm ci --omit=dev --no-audit --no-fund --ignore-scripts >/dev/null)

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Refyn</string>
    <key>CFBundleIdentifier</key><string>com.refyn.prompt-assistant</string>
    <key>CFBundleName</key><string>Refyn</string>
    <key>CFBundleDisplayName</key><string>Refyn</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSMicrophoneUsageDescription</key><string>Refyn records your voice only while you hold the dictation shortcut or press the microphone button, and transcribes it on this Mac.</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP_DIR"
printf 'Built %s\n' "$APP_DIR"
