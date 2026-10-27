# 결정 기록 (ADR)

2026-10-27 작가님 확인. 상세 근거는 `docs/02-plan.md` §1–2, `docs/orca-cli-contract.md`.

| ID | 결정 | 이유 | 대안·후속 |
|---|---|---|---|
| ADR-1 STT | 설치되어 있는 whisper.cpp(`whisper-cli` 1.8.4, Metal)와 `~/.cache/whisper-cpp/ggml-small.bin`(다국어 small)을 재사용 | 추가 다운로드가 없고, 설치를 실측해 확인함 | large-v3-turbo는 벤치마크에서 비교. WhisperKit은 `SpeechRecognizer` 프로토콜 뒤에 붙일 후속 옵션 |
| ADR-2 LLM | llama.cpp 공식 macOS arm64 릴리스(`llama-server`)와 Qwen3-1.7B Q4_K_M을 `.local-models/`에 둔다(gitignore). 127.0.0.1에 무작위 포트·API 키로 띄우는 앱 관리형 서브프로세스 | 프로젝트 폴더 밖 수정 금지 제약. 외부 API 사용 금지 | 다운로드 직전에 URL·용량·SHA256을 보고. EXAONE은 NC 라이선스라 비교 실험에만 사용 |
| ADR-3 빌드 | SwiftPM과 `scripts/build-app.sh`로 .app을 조립하고 ad-hoc 서명. 공증하지 않음 | Xcode 없음(CLT만 있음). 로컬 실행이 목적 | 재빌드하면 마이크 권한을 다시 물을 수 있음 → **2026-10-28 갱신:** 작가님 승인으로 로그인 키체인에 로컬 자체 서명 인증서 `JARVIS Launcher Local Signing`(10년, 코드 서명 전용, 신뢰 설정 안 함)을 만들고 `build-app.sh`가 이것으로 서명. 지정 요구사항이 `identifier + certificate leaf`가 되어 재빌드해도 권한 유지. 인증서가 없으면 ad-hoc으로 되돌아감 |
| ADR-4 기동 | `orca terminal create --command "cd -- '<dir>' && claude --permission-mode plan --session-id <uuid> -n <slug>"` | `agent launch`는 채팅 UI로 열릴 수 있음. 세션 UUID를 JARVIS가 알게 됨 | 화면 footer `plan mode on`으로 확인한 뒤에만 전송 |
| ADR-5 데이터 | JSON 파일에 저장. 기본 위치는 `~/Library/Application Support/<bundle-id>/`, 개발 중에는 `JARVIS_DATA_DIR=.local-data` | 개발 중 폴더 밖 쓰기를 피함. UserDefaults를 쓰지 않음 | 로그인 시 실행은 작가님 승인 후에만 켬 |
| ADR-6 준비 판정 | `tui-idle`만으로는 전송하지 않는다. 화면을 읽어 대화상자 패턴이 있으면 차단 | M0b에서 MCP 승인 대화상자가 떠 있는데도 `tui-idle`이 충족되는 것을 관찰 | 대화상자에 자동 응답하지 않음 |
| ADR-7 받아쓰기 정리 | 받아쓴 말을 `claude -p --model claude-haiku-5-5`로 목표·배경·할 일·조건·확인할 점으로 정리한다. 도구 끔(`--tools ""`), 세션 저장 안 함, 설정·MCP·훅을 읽지 않음, 빈 전용 폴더(`<데이터>/claude-structurer`)에서 실행. 정리본 끝에는 받아쓴 원문을 항상 붙인다. 로컬 모델은 설정에서 고를 수 있는 대안으로 남김 | 2026-10-28 작가님 결정. 로컬 Qwen3-1.7B는 589자 발화에서 할 일을 1개만 뽑는 등 품질이 쓸 수 없는 수준이었음(`qa/evidence/dictation-structure/`) | **원래 요청의 '외부 API 금지'를 이 기능에 한해 바꾼 것이다. 받아쓴 말이 Anthropic으로 전송된다.** 프로젝트 추천·새 프로젝트 메타 프롬프트는 계속 로컬 모델 |
| ADR-8 프롬프트 기록 | Claude Code `UserPromptSubmit` 훅(`build/jarvis-prompt-hook --db .local-data/prompts.sqlite`)이 프롬프트를 SQLite `prompts`에 쓴다. JARVIS는 보낼 때 `launcher_sends`에 받아쓴 원문·프로젝트·스킬을 쓰고, 같은 글(sha256)·5분 이내로 짝짓는다. 설정 탭에서 골라 마크다운 1개로 내보낸다 | 2026-10-28 작가님 결정(저장 시점=훅, SQLite+마크다운 내보내기, 보낸 글+받아쓴 원문, 골라서 1개) | **PRD 5.9 "프롬프트 원문 비저장"을 바꾼 것이다.** 저장 전 `SecretMasker`로 가림. 훅은 표준 출력에 쓰지 않고 항상 exit 0, 1초 제한. `~/.claude/settings.json`은 프로젝트 밖이므로 `scripts/install-prompt-hook.sh`가 미리보기 후 승인 시에만 백업과 함께 항목을 추가 |
