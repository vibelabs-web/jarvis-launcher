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
# 프롬프트 기록 훅(ADR-8). 경로가 바뀌면 ~/.claude/settings.json의 훅 항목도 바뀌어야 하므로 고정 위치에 둔다.
swift build -c "$CONFIG" --product JARVISPromptHook
cp "$(swift build -c "$CONFIG" --show-bin-path)/JARVISPromptHook" build/jarvis-prompt-hook.tmp
codesign --force --sign - --timestamp=none build/jarvis-prompt-hook.tmp
mv -f build/jarvis-prompt-hook.tmp build/jarvis-prompt-hook
echo "built: $APP"
