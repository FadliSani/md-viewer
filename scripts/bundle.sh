#!/bin/zsh
# Builds MDViewer and wraps it in a macOS .app bundle (build/MD Viewer.app).
# The bundle's Info.plist is what registers the Markdown document type, so the
# native Open/Save panels recognise .md files.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)"

APP="build/MD Viewer.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/MDViewer" "$APP/Contents/MacOS/MDViewer"
cp Support/Info.plist "$APP/Contents/Info.plist"
cp Support/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# SwiftMath's fonts live in a SwiftPM resource bundle that it finds via Bundle.module.
for resources in "$BIN"/*.bundle; do
    cp -R "$resources" "$APP/Contents/Resources/"
done
codesign --force --sign - "$APP" >/dev/null

echo "Built $APP"
