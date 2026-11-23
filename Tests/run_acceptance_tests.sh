#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOL="$ROOT/Tools/svstudio-tool"
APP="$ROOT/SVStudio.app"
OUT="$ROOT/Tests/Acceptance"
TMP_BAD="$(mktemp -d)"
trap 'rm -rf "$TMP_BAD"' EXIT

mkdir -p "$OUT"

GOTHIC_SAT="$ROOT/SatellaAvatar/GothicWitch.sat"
if [ ! -f "$GOTHIC_SAT" ] && [ -f "$ROOT/Avatars/GothicWitch.sat" ]; then
    GOTHIC_SAT="$ROOT/Avatars/GothicWitch.sat"
fi

echo "=== 1. Unit & Engine Test Suite (satella-tests) ==="
cd "$ROOT/Source"
swift run satella-tests

echo "=== 2. CLI Validation & Inspection ==="
"$TOOL" validate "$ROOT/Avatars/TestAvatar.sat"
"$TOOL" inspect "$ROOT/Avatars/TestAvatar.sat"
if [ -f "$GOTHIC_SAT" ]; then
    "$TOOL" validate "$GOTHIC_SAT"
    "$TOOL" inspect "$GOTHIC_SAT"
fi

echo "=== 3. CLI Multi-Pose, Expression & Skirt-Lift Render Verification ==="
if [ -f "$GOTHIC_SAT" ]; then
    "$TOOL" render "$GOTHIC_SAT" --expression happy --zoom 3.2 --pan-y 1420 --out "$OUT/gothic_happy_zoom.png" --background black
    "$TOOL" render "$GOTHIC_SAT" --expression surprised --zoom 3.2 --pan-y 1420 --out "$OUT/gothic_surprised_zoom.png" --background transparent
    "$TOOL" render "$GOTHIC_SAT" --param ParamAngleX=-25 --param ParamBodyAngleX=8 --time 1.2 --out "$OUT/gothic_pose_left.png" --background green
    "$TOOL" render "$GOTHIC_SAT" --param ParamSkirtLift=0.92 --out "$OUT/gothic_skirt_lift.png" --background black
fi
"$TOOL" render "$ROOT/Avatars/TestAvatar.sat" --param ParamEyeLOpen=0.0 --param ParamEyeROpen=1.0 --param ParamEyeBallX=-0.8 --param ParamAngleX=22 --expression happy --out "$OUT/test_wink_pose.png" --background black

echo "=== 4. Negative & Security Validation Tests ==="
echo "NOT_A_ZIP" > "$TMP_BAD/corrupt.sat"
if "$TOOL" validate "$TMP_BAD/corrupt.sat" >/dev/null 2>&1; then
    echo "FAIL: corrupt.sat was unexpectedly accepted" && exit 1
fi
echo "  [PASS] corrupt .sat rejected safely"

python3 - "$TMP_BAD/traversal.sat" <<'PY'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1], "w") as z:
    z.writestr("../evil.txt", b"pwned")
    z.writestr("manifest.json", b"{}")
PY
if "$TOOL" validate "$TMP_BAD/traversal.sat" >/dev/null 2>&1; then
    echo "FAIL: path traversal archive was unexpectedly accepted" && exit 1
fi
echo "  [PASS] path traversal archive rejected safely"

python3 - "$TMP_BAD/nomanifest.sat" <<'PY'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1], "w") as z:
    z.writestr("model.json", b"{}")
PY
if "$TOOL" validate "$TMP_BAD/nomanifest.sat" >/dev/null 2>&1; then
    echo "FAIL: missing-manifest archive was unexpectedly accepted" && exit 1
fi
echo "  [PASS] missing manifest rejected safely"

echo "=== 5. SVStudio.app Bundle, Satella Removal & Codesign Verification ==="
test -d "$APP"
test -x "$APP/Contents/MacOS/SVStudio"
test -f "$APP/Contents/Info.plist"
test -f "$APP/Contents/Resources/Avatars/TestAvatar.sat"
if [ -e "$APP/Contents/Resources/Avatars/GothicWitch.sat" ]; then
    echo "FAIL: GothicWitch.sat must not be bundled inside SVStudio.app" && exit 1
fi
codesign --verify --deep --strict --verbose=2 "$APP"
echo "  [PASS] SVStudio.app signed cleanly & contains no Satella/GothicWitch avatar"

echo "=== 6. SVStudio.app Smoke Check ==="
"$APP/Contents/MacOS/SVStudio" --smoke-check --avatar "$ROOT/Avatars/TestAvatar.sat"

echo "=== 7. Native macOS GUI Launch & Window Verification ==="
open "$APP"
sleep 2
PID=$(pgrep -f "$APP/Contents/MacOS/SVStudio" || true)
test -n "$PID"
echo "  [PASS] SVStudio.app running live with PID $PID"
osascript -e 'tell application "SVStudio" to quit' >/dev/null 2>&1 || kill "$PID"
sleep 1

echo "=== 8. Signed Self-Contained DMG Verification ==="
DMG="$ROOT/SVStudio-1.0.0.dmg"
test -f "$DMG"
test -f "$DMG.sha256"
(cd "$ROOT" && shasum -a 256 -c "$(basename "$DMG").sha256")
codesign --verify --strict --verbose=2 "$DMG"
hdiutil verify "$DMG"
MNT_DIR="$(mktemp -d)"
hdiutil attach "$DMG" -nobrowse -readonly -mountpoint "$MNT_DIR"
trap 'hdiutil detach "$MNT_DIR" >/dev/null 2>&1 || true; rm -rf "$TMP_BAD" "$MNT_DIR"' EXIT
test -d "$MNT_DIR/SVStudio.app"
test -L "$MNT_DIR/Applications"
test -f "$MNT_DIR/Sample Avatars/TestAvatar.sat"
test -f "$MNT_DIR/Read Me First.txt"
if [ -e "$MNT_DIR/Sample Avatars/GothicWitch.sat" ] || [ -e "$MNT_DIR/SVStudio.app/Contents/Resources/Avatars/GothicWitch.sat" ]; then
    echo "FAIL: GothicWitch.sat must not be bundled inside SVStudio-1.0.0.dmg" && exit 1
fi
codesign --verify --deep --strict "$MNT_DIR/SVStudio.app"
"$MNT_DIR/SVStudio.app/Contents/MacOS/SVStudio" --smoke-check --avatar "$MNT_DIR/Sample Avatars/TestAvatar.sat"
hdiutil detach "$MNT_DIR"
echo "  [PASS] SVStudio-1.0.0.dmg signed, checksummed, clean, and verified"

echo "ALL ACCEPTANCE TESTS PASSED!"
