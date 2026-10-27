#!/bin/zsh
# 개발 실행: 데이터는 프로젝트 안 .local-data 에 둔다(ADR-5). 실행 중인 인스턴스는 먼저 종료한다.
set -euo pipefail
cd "$(dirname "$0")/.."
pkill -x JARVISLauncher 2>/dev/null || true
mkdir -p .local-data
args=(--env "JARVIS_DATA_DIR=$PWD/.local-data")
[[ "${JARVIS_DEV_HOOKS:-}" == "1" ]] && args+=(--env JARVIS_DEV_HOOKS=1)
open -n "${args[@]}" build/JARVISLauncher.app
echo "started (data: $PWD/.local-data)"
