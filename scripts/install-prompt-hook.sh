#!/bin/zsh
# 프롬프트 기록 훅(ADR-8)을 ~/.claude/settings.json 의 hooks.UserPromptSubmit 에 추가·제거한다.
# 이 파일은 프로젝트 폴더 밖이므로 기본은 미리보기만 한다. 작가님 승인 뒤에만 --apply.
#   scripts/install-prompt-hook.sh            바뀔 내용만 보여 줌(파일을 바꾸지 않음)
#   scripts/install-prompt-hook.sh --apply    백업 후 항목 추가(이미 있으면 그대로)
#   scripts/install-prompt-hook.sh --remove   백업 후 이 훅 항목만 제거
set -euo pipefail
cd "$(dirname "$0")/.."
MODE="${1:-preview}"
SETTINGS="$HOME/.claude/settings.json"
HOOK="$PWD/build/jarvis-prompt-hook"
DB="$PWD/.local-data/prompts.sqlite"
[[ -x "$HOOK" ]] || { echo "훅 실행 파일이 없습니다: $HOOK (scripts/build-app.sh 먼저)"; exit 1; }

python3 -I - "$MODE" "$SETTINGS" "$HOOK" "$DB" <<'PY'
import json, shlex, sys, shutil, time, difflib, os
mode, settings, hook, db = sys.argv[1:5]
command = f"{shlex.quote(hook)} --db {shlex.quote(db)}"
entry = {"hooks": [{"type": "command", "command": command, "timeout": 5}]}
marker = "jarvis-prompt-hook"

with open(settings, encoding="utf-8") as f:
    original = f.read()
data = json.loads(original)
groups = data.setdefault("hooks", {}).setdefault("UserPromptSubmit", [])

def is_ours(g):
    return any(marker in (h.get("command") or "") for h in g.get("hooks", []))

installed = any(is_ours(g) for g in groups)
if mode in ("preview", "--apply"):
    if installed:
        print("이미 설치되어 있습니다. 바뀌는 것이 없습니다.")
        sys.exit(0)
    groups.append(entry)
elif mode == "--remove":
    if not installed:
        print("설치되어 있지 않습니다.")
        sys.exit(0)
    data["hooks"]["UserPromptSubmit"] = [g for g in groups if not is_ours(g)]
else:
    print("사용법: install-prompt-hook.sh [--apply|--remove]"); sys.exit(2)

updated = json.dumps(data, ensure_ascii=False, indent=2) + "\n"
diff = difflib.unified_diff(original.splitlines(), updated.splitlines(), settings, settings + " (변경 후)", lineterm="", n=2)
print("\n".join(diff))
if mode == "preview":
    print("\n(미리보기만 했습니다. 파일은 바뀌지 않았습니다.)")
    sys.exit(0)
backup = f"{settings}.bak-jarvis-{time.strftime('%Y%m%d-%H%M%S')}"
shutil.copy2(settings, backup)
tmp = settings + ".jarvis-tmp"
with open(tmp, "w", encoding="utf-8") as f:
    f.write(updated)
os.replace(tmp, settings)
print(f"\n적용했습니다. 백업: {backup}")
PY
