#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SRC="$ROOT/Source"
APP="$ROOT/SVStudio.app"

echo "==> Building release SVStudio & svstudio-tool binaries..."
cd "$SRC"
swift build -c release --product SVStudio
swift build -c release --product svstudio-tool
BIN_DIR="$(swift build -c release --product SVStudio --show-bin-path)"
BIN="$BIN_DIR/SVStudio"
TOOL_BIN="$BIN_DIR/svstudio-tool"

mkdir -p "$ROOT/Tools"
cp "$TOOL_BIN" "$ROOT/Tools/svstudio-tool"
chmod +x "$ROOT/Tools/svstudio-tool"

echo "==> Assembling $APP (clean open-source bundle without GothicWitch/Satella)..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Avatars"
cp "$BIN" "$APP/Contents/MacOS/SVStudio"
chmod +x "$APP/Contents/MacOS/SVStudio"
cp "$SRC/Packaging/Info.plist" "$APP/Contents/Info.plist"
if [ -f "$ROOT/Avatars/TestAvatar.sat" ]; then
    cp "$ROOT/Avatars/TestAvatar.sat" "$APP/Contents/Resources/Avatars/TestAvatar.sat"
fi

ICONSET="$SRC/.build/SVStudio.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
swift -e '
import AppKit
func drawIcon(size: Int, out: String) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let bg = NSBezierPath(roundedRect: rect.insetBy(dx: CGFloat(size)*0.06, dy: CGFloat(size)*0.06), xRadius: CGFloat(size)*0.22, yRadius: CGFloat(size)*0.22)
    let grad = NSGradient(colors: [NSColor(red: 0.08, green: 0.06, blue: 0.14, alpha: 1), NSColor(red: 0.24, green: 0.11, blue: 0.42, alpha: 1)])!
    grad.draw(in: bg, angle: 120)
    NSColor(red: 0.72, green: 0.56, blue: 0.96, alpha: 0.48).setStroke()
    bg.lineWidth = max(1.0, CGFloat(size)*0.025)
    bg.stroke()
    let c = CGPoint(x: CGFloat(size)*0.5, y: CGFloat(size)*0.5)
    let rOut = CGFloat(size)*0.32
    let rIn = CGFloat(size)*0.11
    let star = NSBezierPath()
    for i in 0..<8 {
        let ang = CGFloat(i) * .pi / 4.0 + .pi / 2.0
        let rad = (i % 2 == 0) ? rOut : rIn
        let pt = CGPoint(x: c.x + cos(ang)*rad, y: c.y + sin(ang)*rad)
        if i == 0 { star.move(to: pt) } else { star.line(to: pt) }
    }
    star.close()
    NSColor(red: 0.85, green: 0.72, blue: 1.0, alpha: 0.95).setFill()
    star.fill()
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
}
let dir = "'$ICONSET'"
for s in [16, 32, 128, 256, 512] {
    drawIcon(size: s, out: "\(dir)/icon_\(s)x\(s).png")
    drawIcon(size: s*2, out: "\(dir)/icon_\(s)x\(s)@2x.png")
}
'
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon" "$APP/Contents/Info.plist"

SIGN_ID="${SVSTUDIO_CODESIGN_IDENTITY:--}"
codesign --force --deep --sign "$SIGN_ID" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
echo "==> Done & signed: $APP"
