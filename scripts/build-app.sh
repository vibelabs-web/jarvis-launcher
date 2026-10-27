#!/bin/zsh
# SwiftPM으로 빌드하고 build/JARVISLauncher.app 을 조립해 ad-hoc 서명한다(ADR-3).
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
swift build -c "$CONFIG" --product JARVISLauncher
BIN="$(swift build -c "$CONFIG" --show-bin-path)/JARVISLauncher"
APP="build/JARVISLauncher.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/JARVISLauncher"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --verbose=2 "$APP"
echo "built: $APP"
