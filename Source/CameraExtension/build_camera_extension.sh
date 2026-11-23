#!/bin/zsh
set -euo pipefail

# Compiles SatellaCameraProvider.swift into a standalone .systemextension bundle structure.
# Note: Activating a CMIOExtension under macOS SIP requires signing both Satella.app and
# dev.satella.camera.extension.systemextension with an Apple Developer ID + provisioning profile
# containing `com.apple.developer.system-extension.install`.

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/Source/.build/CameraExtension/dev.svstudio.camera.extension.systemextension"
rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS"

swiftc -parse-as-library -O -target arm64-apple-macos14.0 \
    -sdk /Library/Developer/CommandLineTools/SDKs/MacOSX27.2.sdk \
    "$ROOT/Source/CameraExtension/SatellaCameraProvider.swift" \
    -framework Foundation -framework CoreMediaIO -framework CoreMedia -framework CoreVideo -framework CoreAudio \
    -o "$OUT/Contents/MacOS/dev.svstudio.camera.extension"

cp "$ROOT/Source/CameraExtension/Info.plist" "$OUT/Contents/Info.plist"
chmod +x "$OUT/Contents/MacOS/dev.svstudio.camera.extension"
echo "Built CMIOExtension bundle at $OUT"
