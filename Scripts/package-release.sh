#!/bin/sh
# Builds an Apple Silicon Refyn release package with portable Node and split offline model assets.
# Usage: Scripts/package-release.sh [version]
set -eu

VERSION=${1:-0.1.0}
case "$VERSION" in
  ""|*[!0-9.]*|.*|*.|*..*) echo "Version must use numeric dot-separated components (for example 0.1.0)." >&2; exit 2 ;;
esac

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
RELEASE_DIR=${REFYN_RELEASE_DIR:-"$ROOT_DIR/.build/release-package"}
TOOLS_DIR="$ROOT_DIR/.build/release-tools"
NODE_VERSION=v24.22.0
NODE_ARCHIVE_NAME="node-$NODE_VERSION-darwin-arm64.tar.gz"
NODE_URL="https://nodejs.org/dist/$NODE_VERSION/$NODE_ARCHIVE_NAME"
NODE_SHA256=6a9724d9b50a5f22b4816cded441b5a8d9ddae546191a5e5b7efa5a5e2ee26d5
NODE_ARCHIVE="$TOOLS_DIR/$NODE_ARCHIVE_NAME"
NODE_ROOT="$TOOLS_DIR/node-$NODE_VERSION-darwin-arm64"
NODE_BIN="$NODE_ROOT/bin/node"
DEFAULT_SPEECH_MODEL_DIR="$HOME/Library/Application Support/Refyn/SpeechModels/models/argmaxinc/whisperkit-coreml/openai_whisper-base.en"
SPEECH_MODEL_DIR=${REFYN_SPEECH_MODEL_DIR:-$DEFAULT_SPEECH_MODEL_DIR}
DEFAULT_QWEN_MODEL_DIR="$HOME/Library/Application Support/Refyn/Models/models/mlx-community/Qwen3-4B-4bit"
QWEN_MODEL_DIR=${REFYN_QWEN_MODEL_DIR:-$DEFAULT_QWEN_MODEL_DIR}
APP_DIR="$RELEASE_DIR/Refyn.app"
PACKAGE_DIR="$RELEASE_DIR/Refyn-$VERSION-macos-arm64"

[ "$(uname -m)" = "arm64" ] || { echo "Refyn release builds require an Apple Silicon Mac (arm64)." >&2; exit 1; }
for tool in curl tar split shasum ditto hdiutil codesign; do
  command -v "$tool" >/dev/null || { echo "Required release tool is missing: $tool" >&2; exit 1; }
done
mkdir -p "$TOOLS_DIR" "$RELEASE_DIR"

[ -f "$SPEECH_MODEL_DIR/AudioEncoder.mlmodelc/model.mil" ] || {
  echo "A downloaded WhisperKit English Base model is required to package voice dictation." >&2
  echo "Set REFYN_SPEECH_MODEL_DIR to a local openai_whisper-base.en model directory." >&2
  exit 1
}
[ -f "$QWEN_MODEL_DIR/config.json" ] && [ -f "$QWEN_MODEL_DIR/model.safetensors" ] || {
  echo "A downloaded mlx-community/Qwen3-4B-4bit model is required to package offline optimization." >&2
  echo "Set REFYN_QWEN_MODEL_DIR to its local model directory." >&2
  exit 1
}

if [ ! -f "$NODE_ARCHIVE" ] || ! printf '%s  %s\n' "$NODE_SHA256" "$NODE_ARCHIVE" | shasum -a 256 -c - >/dev/null 2>&1; then
  echo "› Downloading portable Node.js $NODE_VERSION"
  curl --fail --location --retry 3 --retry-all-errors "$NODE_URL" --output "$NODE_ARCHIVE"
fi
printf '%s  %s\n' "$NODE_SHA256" "$NODE_ARCHIVE" | shasum -a 256 -c -

if [ ! -x "$NODE_BIN" ]; then
  rm -rf "$NODE_ROOT"
  tar -xzf "$NODE_ARCHIVE" -C "$TOOLS_DIR"
fi
[ -x "$NODE_BIN" ] || { echo "Node archive did not contain $NODE_BIN" >&2; exit 1; }
[ "$("$NODE_BIN" --version)" = "$NODE_VERSION" ] || { echo "Unexpected bundled Node runtime version." >&2; exit 1; }

echo "› Building Refyn $VERSION with the bundled Node runtime"
PATH="$NODE_ROOT/bin:$PATH" \
REFYN_APP_DIR="$APP_DIR" \
REFYN_APP_VERSION="$VERSION" \
REFYN_APP_BUILD=${REFYN_APP_BUILD:-1} \
REFYN_NODE_BINARY="$NODE_BIN" \
REFYN_NODE_LICENSE="$NODE_ROOT/LICENSE" \
REFYN_SPEECH_MODEL_DIR="$SPEECH_MODEL_DIR" \
  "$ROOT_DIR/Scripts/build-app.sh" release

echo "› Verifying app bundle and bundled helper"
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_DIR/Contents/Info.plist" | grep -Fx "$VERSION" >/dev/null
codesign --verify --deep --strict "$APP_DIR"
file "$APP_DIR/Contents/Resources/Node/bin/node" | grep -q 'arm64'
HELPER="$APP_DIR/Contents/Resources/RefineHelper/dist/src/main.js"
[ -f "$HELPER" ] || { echo "Bundled helper is missing." >&2; exit 1; }
HELLO=$(printf '{"protocol":2,"id":"release-smoke","method":"hello","params":{}}\n' | "$APP_DIR/Contents/Resources/Node/bin/node" "$HELPER")
printf '%s\n' "$HELLO" | grep -F '"protocol":2' >/dev/null
printf '%s\n' "$HELLO" | grep -F '"node":"v24.22.0"' >/dev/null
echo "$HELLO"
SPEECH_MODEL="$APP_DIR/Contents/Resources/SpeechModels/openai_whisper-base.en"
for component in AudioEncoder.mlmodelc TextDecoder.mlmodelc MelSpectrogram.mlmodelc; do
  [ -f "$SPEECH_MODEL/$component/model.mil" ] || { echo "Bundled speech model is missing $component." >&2; exit 1; }
done
[ -f "$APP_DIR/Contents/Resources/Licenses/OpenAI-Whisper-LICENSE.txt" ] || { echo "Whisper model license is missing." >&2; exit 1; }
echo "Bundled WhisperKit English Base model: $(du -sh "$SPEECH_MODEL" | awk '{print $1}')"
echo "› Smoke-testing bundled dictation model offline"
REFINE_SUPPORT_DIR="$APP_DIR/Contents/Resources" swift test --filter SpeechTranscriberModelTests

QWEN_ARCHIVE_NAME="Refyn-$VERSION-Qwen3-4B-4bit.tar.gz"
QWEN_ARCHIVE="$RELEASE_DIR/$QWEN_ARCHIVE_NAME"
QWEN_SHA="$QWEN_ARCHIVE.sha256"
QWEN_PART_PREFIX="$QWEN_ARCHIVE.part-"
QWEN_INSTALL="$RELEASE_DIR/Refyn-$VERSION-Qwen3-4B-4bit-Install.txt"
QWEN_MODEL_PARENT=$(dirname "$(dirname "$QWEN_MODEL_DIR")")
rm -f "$QWEN_ARCHIVE" "$QWEN_SHA" "$QWEN_INSTALL" "${QWEN_PART_PREFIX}"*
echo "› Packaging offline Qwen3 4B model assets"
tar -czf "$QWEN_ARCHIVE" \
  -C "$QWEN_MODEL_PARENT" mlx-community/Qwen3-4B-4bit \
  -C "$ROOT_DIR/Resources/Licenses" Apache-2.0.txt
tar -tzf "$QWEN_ARCHIVE" >/dev/null
(cd "$RELEASE_DIR" && shasum -a 256 "$QWEN_ARCHIVE_NAME" > "$(basename "$QWEN_SHA")")
# GitHub limits each release asset to less than 2 GiB, so split the model archive into safe parts.
split -b 1800m "$QWEN_ARCHIVE" "$QWEN_PART_PREFIX"
for part in "${QWEN_PART_PREFIX}"*; do
  part_bytes=$(stat -f%z "$part")
  [ "$part_bytes" -lt 2147483648 ] || { echo "Qwen model part exceeds GitHub's 2 GiB asset limit: $part" >&2; exit 1; }
done
expected_archive_hash=$(awk '{print $1}' "$QWEN_SHA")
actual_archive_hash=$(cat "${QWEN_PART_PREFIX}"* | shasum -a 256 | awk '{print $1}')
[ "$actual_archive_hash" = "$expected_archive_hash" ] || { echo "Qwen model archive parts failed their reassembly check." >&2; exit 1; }
rm "$QWEN_ARCHIVE"
cat > "$QWEN_INSTALL" <<EOF
Offline Qwen3 4B · 4-bit model for Refyn $VERSION

Download every Refyn-$VERSION-Qwen3-4B-4bit.tar.gz.part-* file into this folder.
Join the pieces and verify the combined archive:

  cat Refyn-$VERSION-Qwen3-4B-4bit.tar.gz.part-* > Refyn-$VERSION-Qwen3-4B-4bit.tar.gz
  shasum -a 256 -c Refyn-$VERSION-Qwen3-4B-4bit.tar.gz.sha256

Install the model in Refyn's local cache:

  mkdir -p "\$HOME/Library/Application Support/Refyn/Models/models"
  tar -xzf Refyn-$VERSION-Qwen3-4B-4bit.tar.gz -C "\$HOME/Library/Application Support/Refyn/Models/models"

Then open Settings > Model and choose Load model. The archive includes the Apache-2.0 license.
Keep the archive parts if you want a backup.
EOF

rm -rf "$PACKAGE_DIR"
mkdir -p "$PACKAGE_DIR"
ditto "$APP_DIR" "$PACKAGE_DIR/Refyn.app"
ln -s /Applications "$PACKAGE_DIR/Applications"
cat > "$PACKAGE_DIR/First Run.txt" <<EOF
Refyn $VERSION · macOS Apple Silicon

Install
Drag Refyn.app to Applications and open it. This QA build is ad-hoc signed and is not notarized.

Prompt optimization model
Open Settings > Model and choose Download model. The app downloads Qwen3 4B 4-bit from:
https://huggingface.co/mlx-community/Qwen3-4B-4bit

The model download is about 2.3 GB and needs internet once. After it finishes, prompt optimization runs locally and works offline. Allow about 8 GB of available unified memory.
To set up without downloading from the app, get every split Qwen model asset from the same GitHub release, reassemble and install it using the included Qwen install instructions, then choose Load model in Settings > Model.

Voice dictation
The English WhisperKit Base speech model is included in the app bundle, so dictation is ready without a separate model download. Audio is transcribed on this Mac. Tiny and Small English models remain available as optional downloads in Settings > Voice. The bundled model and its MIT license are in Refyn.app/Contents/Resources.
The OpenAI Whisper model weights are MIT licensed; see Refyn.app/Contents/Resources/Licenses/OpenAI-Whisper-LICENSE.txt.

The workspace analysis helper includes a portable Node.js $NODE_VERSION runtime; users do not need to install Node.js.

This package is ad-hoc signed for local QA. A public release still requires Developer ID signing and Apple notarization.
EOF

ZIP_PATH="$RELEASE_DIR/Refyn-$VERSION-macos-arm64.zip"
DMG_PATH="$RELEASE_DIR/Refyn-$VERSION-macos-arm64.dmg"
rm -f "$ZIP_PATH" "$DMG_PATH"
echo "› Creating ZIP"
ditto -c -k --sequesterRsrc --keepParent "$PACKAGE_DIR" "$ZIP_PATH"
echo "› Creating drag-to-Applications disk image"
hdiutil create -volname "Refyn $VERSION" -srcfolder "$PACKAGE_DIR" -ov -format UDZO "$DMG_PATH" >/dev/null
(cd "$RELEASE_DIR" && shasum -a 256 "$(basename "$ZIP_PATH")" "$(basename "$DMG_PATH")" "$(basename "$QWEN_SHA")" "$(basename "$QWEN_INSTALL")" > SHA256SUMS.txt)
for part in "${QWEN_PART_PREFIX}"*; do
  (cd "$RELEASE_DIR" && shasum -a 256 "$(basename "$part")") >> "$RELEASE_DIR/SHA256SUMS.txt"
done

echo "Release files:"
ls -lh "$ZIP_PATH" "$DMG_PATH" "$RELEASE_DIR/SHA256SUMS.txt" "$QWEN_SHA" "$QWEN_INSTALL" "${QWEN_PART_PREFIX}"*
echo "App bundle: $APP_DIR"
