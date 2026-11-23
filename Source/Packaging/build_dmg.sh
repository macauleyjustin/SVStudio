#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
APP="$ROOT/SVStudio.app"
DMG="$ROOT/SVStudio-1.0.0.dmg"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

echo "==> Building fresh release SVStudio.app..."
"$ROOT/Source/Packaging/build_app.sh"

echo "==> Staging self-contained DMG contents..."
ditto "$APP" "$STAGE/SVStudio.app"
ln -s /Applications "$STAGE/Applications"

mkdir -p "$STAGE/Sample Avatars"
if [ -f "$ROOT/Avatars/TestAvatar.sat" ]; then
    cp "$ROOT/Avatars/TestAvatar.sat" "$STAGE/Sample Avatars/TestAvatar.sat"
fi

cat > "$STAGE/Read Me First.txt" <<'TXT'
SVStudio — Open-Source Native macOS VTuber Player (.sat)
=========================================================

Installation:
1. Drag SVStudio.app onto the Applications folder icon.
2. Launch SVStudio from Applications.
   (If macOS Gatekeeper warns on an ad-hoc build: right-click SVStudio.app -> Open -> Open.)
3. Sample avatar ("TestAvatar.sat") is bundled inside SVStudio.app and included in
   "Sample Avatars/". Drag any .sat file onto the window (or use File -> Open Avatar) to load it.

Face Tracking, Mic Lip Sync & Output:
- Tracking tab: Enable Face Tracking to use Apple Vision locally for real-time head,
  brow, eye, mouth, and facial expression tracking, plus Microphone Lip-Sync.
- Rig & FX tab: Expressive emotions, per-avatar adaptive physics, schema-defined drag
  reactions, and full VTube Studio parameter inspector.
- Output tab -> Virtual Webcam Output / OBS Clean Feed (Cmd+Shift+B):
  Push live Metal frames to OBS Virtual Camera or open a clean borderless capture window.
TXT

rm -f "$DMG" "$DMG.sha256"
echo "==> Creating compressed disk image $DMG..."
hdiutil create -volname "SVStudio" -srcfolder "$STAGE" -ov -format UDZO "$DMG"

SIGN_ID="${SVSTUDIO_CODESIGN_IDENTITY:--}"
codesign --force --sign "$SIGN_ID" "$DMG"
codesign --verify --strict --verbose=2 "$DMG"
hdiutil verify "$DMG"
(cd "$ROOT" && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")
echo "==> Signed & Verified DMG ready: $DMG ($(stat -f%z "$DMG") bytes)"
