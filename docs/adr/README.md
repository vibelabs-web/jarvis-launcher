# 결정 기록 (ADR)

2026-10-27 작가님 확인. 상세 근거는 `docs/02-plan.md` §1–2, `docs/orca-cli-contract.md`.

| ID | 결정 | 이유 | 대안·후속 |
|---|---|---|---|
| ADR-1 STT | 설치되어 있는 whisper.cpp(`whisper-cli` 1.8.4, Metal)와 `~/.cache/whisper-cpp/ggml-small.bin`(다국어 small)을 재사용 | 추가 다운로드가 없고, 설치를 실측해 확인함 | large-v3-turbo는 벤치마크에서 비교. WhisperKit은 `SpeechRecognizer` 프로토콜 뒤에 붙일 후속 옵션 |
| ADR-2 LLM | llama.cpp 공식 macOS arm64 릴리스(`llama-server`)와 Qwen3-1.7B Q4_K_M을 `.local-models/`에 둔다(gitignore). 127.0.0.1에 무작위 포트·API 키로 띄우는 앱 관리형 서브프로세스 | 프로젝트 폴더 밖 수정 금지 제약. 외부 API 사용 금지 | 다운로드 직전에 URL·용량·SHA256을 보고. EXAONE은 NC 라이선스라 비교 실험에만 사용 |
| ADR-3 빌드 | SwiftPM과 `scripts/build-app.sh`로 .app을 조립하고 ad-hoc 서명. 공증하지 않음 | Xcode 없음(CLT만 있음). 로컬 실행이 목적 | 재빌드하면 마이크 권한을 다시 물을 수 있음(알려진 한계) |
| ADR-4 기동 | `orca terminal create --command "cd -- '<dir>' && claude --permission-mode plan --session-id <uuid> -n <slug>"` | `agent launch`는 채팅 UI로 열릴 수 있음. 세션 UUID를 JARVIS가 알게 됨 | 화면 footer `plan mode on`으로 확인한 뒤에만 전송 |
| ADR-5 데이터 | JSON 파일에 저장. 기본 위치는 `~/Library/Application Support/<bundle-id>/`, 개발 중에는 `JARVIS_DATA_DIR=.local-data` | 개발 중 폴더 밖 쓰기를 피함. UserDefaults를 쓰지 않음 | 로그인 시 실행은 작가님 승인 후에만 켬 |
| ADR-6 준비 판정 | `tui-idle`만으로는 전송하지 않는다. 화면을 읽어 대화상자 패턴이 있으면 차단 | M0b에서 MCP 승인 대화상자가 떠 있는데도 `tui-idle`이 충족되는 것을 관찰 | 대화상자에 자동 응답하지 않음 |
