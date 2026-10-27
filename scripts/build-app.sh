#!/bin/zsh
# SwiftPM으로 빌드하고 build/JARVISLauncher.app 을 조립해 ad-hoc 서명한다(ADR-3).
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
# 서명 신원: 로그인 키체인의 로컬 자체 서명 인증서가 있으면 그것으로(지정 요구사항 = 번들 ID + 인증서 → 재빌드해도
# 마이크·'문서' 폴더 권한 유지, ADR-3 갱신). 없으면 ad-hoc(빌드마다 권한을 다시 물음).
SIGN_ID="$(security find-identity -p codesigning 2>/dev/null | awk '/"JARVIS Launcher Local Signing"/ {print $2; exit}')"
SIGN_ID="${SIGN_ID:--}"
swift build -c "$CONFIG" --product JARVISLauncher
BIN="$(swift build -c "$CONFIG" --show-bin-path)/JARVISLauncher"
APP="build/JARVISLauncher.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/JARVISLauncher"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign "$SIGN_ID" --timestamp=none "$APP"
codesign --verify --verbose=2 "$APP"
# 프롬프트 기록 훅(ADR-8). 경로가 바뀌면 ~/.claude/settings.json의 훅 항목도 바뀌어야 하므로 고정 위치에 둔다.
swift build -c "$CONFIG" --product JARVISPromptHook
cp "$(swift build -c "$CONFIG" --show-bin-path)/JARVISPromptHook" build/jarvis-prompt-hook.tmp
codesign --force --sign "$SIGN_ID" --timestamp=none build/jarvis-prompt-hook.tmp
mv -f build/jarvis-prompt-hook.tmp build/jarvis-prompt-hook
echo "built: $APP (sign: $([[ "$SIGN_ID" == "-" ]] && echo ad-hoc || echo "JARVIS Launcher Local Signing"))"
