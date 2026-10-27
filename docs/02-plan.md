# JARVIS Launcher — 구현 계획 (docs/02-plan.md 초안)

> 상태: 작가님 승인 완료 (2026-10-27). Spike 0 원문은 `docs/orca-cli-contract.md`, `qa/evidence/spike0/` 참조.

## Context

작가님은 Orca에서 Claude Code 세션 여러 개를 동시에 운영한다. 요청 하나를 보내려 해도 매번 해당 터미널을 찾아 길게 입력해야 한다. JARVIS Launcher는 메뉴바에 상주하는 macOS 앱이다. 핫키를 누르면 가운데 패널이 뜨고, 텍스트나 로컬 받아쓰기로 입력한 내용을 앱이 추천한 Orca 세션으로 **작가님 확인 후 1회** 보낸다. 새 프로젝트라면 메타 프롬프트를 만들고 폴더를 만든 뒤, 새 Orca 터미널에서 Claude Code를 플랜 모드로 시작한다. 범위의 기준은 `docs/01-prd.md`(승인 완료)이고, 의도는 `docs/00-intent.md`다.

## 1. Spike 0 사전 확인 결과 (2026-10-27, 이 Mac에서 실측, 읽기 전용 명령만 사용)

| 항목 | 실측 결과 | 판정 |
|---|---|---|
| 환경 | macOS 26.5.2, Apple M1 Pro, 32GB, 디스크 여유 200GiB | — |
| 빌드 도구 | **Xcode 없음**, CommandLineTools만 있음(Swift 6.3.3). `Testing.framework`(Swift Testing) 사용 가능, XCTest는 없음. cmake 없음 | SwiftPM + 번들 조립 스크립트 |
| Orca | `/Applications/Orca.app/.../bin/orca` 1.4.242. runtime `ready` | G0 대부분 충족 |
| 하위 명령 `--help` | `orca terminal list --help`는 `Unknown command`를 냄. 하위 명령 도움말의 정식 경로는 `orca agent-context --json`(schemaVersion 1, 명령 288개)이며 계약 근거로 이것을 사용 | 기록 |
| `terminal list --json` | `handle, ptyId, incarnationId, orphaned, worktreeId(repoId::path), worktreePath, branch, tabId, leafId, title, paneTitle, connected, writable, lastOutputAt, preview, executionHostId, agentIdentity("claude"/null)` + `hostScope{hostIds, omittedHostIds}` | 경로·호스트·에이전트 종류 식별 가능 |
| Claude 세션 ID | `terminal list/show` 어디에도 **Claude 세션 ID가 없음** | 같은 경로에 Claude가 둘이면 자동 매칭 금지(PRD 5.6) |
| `terminal show --json` | 위 필드 + `agentWait, paneRuntimeId, rendererGraphEpoch` | 전송 직전 재검증에 사용 |
| `terminal read --screen --json` | `source: screen`, `tail[]`. 이 세션 화면에서 `⏸ plan mode on (shift+tab to cycle)` 줄을 실제로 읽음 | **플랜 모드를 화면으로 검증 가능 (G1)** |
| `terminal send` | `--text --enter --wait-submit <s> --retry-request <id> --json`. 노트: "입력 수락과 제출 관찰을 분리 보고", "wait-submit 타임아웃 시 재전송하지 않음", retry ID는 페이로드와 프로세스 incarnation에 묶임 | FR-08 `전송 확인/상태 불명` 매핑 가능 |
| `terminal wait` | `--for exit\|tui-idle --timeout-ms` | Claude 준비 상태 대기 |
| `terminal create` | `--worktree <selector> --title --command <text> --focus --json`, 생성 멱등성 capability `terminal.create-idempotency.v2` | 새 터미널 + 명령 실행 |
| 폴더 등록 | `orca repo add --path <path>`. 기존 repo 중 `kind: folder` 1개 존재. capability `agent.launch.create-folder-workspace.v1`, `folder-workspace.path-status.v1` | Git 없는 빈 폴더 등록 가능성 높음. **쓰기 동작이라 M0b에서 테스트 폴더로 실증** |
| `agent launch` | `--surface chat\|terminal`. 설정에 따라 구조화 채팅으로 열릴 수 있음 | **사용하지 않음**. `terminal create --command "claude …"`로 TUI 보장 |
| 호스트 | `host list`: local(this machine), ssh 1개(미연결), environment 1개(멕미니, omitted) | MVP는 `executionHostId == local`만 전송 허용 |
| 스킬 | `orca skills installed --json`: 809개, `providers`에 claude 122개, `sourceLabel`로 Claude Code home·Claude plugin 구분. 파일 시스템: `~/.claude/skills` 94개, `~/.claude/commands` 14개 | 파일 스캔 + Orca 목록 병합 |
| Claude Code | 2.1.311. `--permission-mode <acceptEdits\|auto\|bypassPermissions\|manual\|dontAsk\|plan>`, `--session-id <uuid>`, `-n/--name` 존재 | `claude --permission-mode plan --session-id <uuid> -n <slug>` |
| Whisper | `whisper-cli`(whisper.cpp 1.8.4, brew, Metal 로드 확인). 모델: `~/.cache/whisper-cpp/ggml-small.bin`(다국어 small, 488MB), `~/whisper-models/ggml-large-v3-turbo.bin`(1.6GB) | **재사용 가능, 추가 다운로드 0** |
| LLM | llama.cpp 미설치. Qwen3-1.7B 없음(Ollama에는 qwen3:4b, exaone3.5만 있고 서버는 꺼져 있음) | 프로젝트 폴더 안에 내려받음(아래 ADR-2) |

아직 확인하지 못한 항목(M0b에서 테스트 전용 폴더·터미널로 실증한다. 기존 세션에는 보내지 않는다):
- `repo add`로 빈 폴더를 등록한 뒤 `terminal create --worktree path:<dir>`가 그 폴더를 cwd로 하는지 확인
- 테스트 터미널에서 `send --wait-submit`이 돌려주는 JSON receipt 필드
- 테스트 폴더의 등록 해제 수단. 도움말에는 `repo rm`이 없고 `project setup-delete`가 후보다. 해제 수단이 없으면 테스트 등록이 Orca 목록에 남는다는 점을 보고한다.
- `whisper-cli --help`, `whisper-server` 유무, `llama-server --help`(`--api-key`, JSON schema 출력, thinking 끄기)

## 2. 결정 기록 (ADR, 작가님 확인 완료)

- **ADR-1 STT:** 이미 설치된 whisper.cpp(`whisper-cli`)를 재사용하고 기본 모델은 `ggml-small.bin`으로 한다. 벤치마크에서는 large-v3-turbo도 비교한다. WhisperKit은 `SpeechRecognizer` 프로토콜 뒤에 둘 후속 옵션이다. 마이크 → 16kHz mono WAV를 앱 임시 폴더에 쓰고, 전사가 끝나면 즉시 삭제한다.
- **ADR-2 LLM:** llama.cpp 공식 macOS arm64 릴리스(`llama-server`, 수십 MB)와 Qwen3-1.7B Instruct Q4_K_M GGUF(약 1.1~1.3GB)를 `jarvis-launcher/.local-models/`에 받고 `.gitignore`에 넣는다. **다운로드는 M3 시작 직전에 정확한 URL·용량·SHA256을 보고하고 진행한다.** 앱이 관리하는 서브프로세스로 띄우며 `127.0.0.1`, 실행마다 무작위 포트와 무작위 API 키를 쓴다. 첫 요청 때 로드하고 유휴 시 종료한다. EXAONE은 NC 라이선스 때문에 비교 실험에만 쓰고 배포에는 넣지 않는다.
- **ADR-3 빌드·서명:** SwiftPM으로 빌드하고 `scripts/build-app.sh`가 `build/JARVISLauncher.app`을 조립한다(Info.plist: `LSUIElement`, `NSMicrophoneUsageDescription`). ad-hoc 서명(`codesign -s -`)으로 로컬에서 실행하며 공증은 하지 않는다. 재빌드하면 마이크 권한을 다시 물을 수 있는데, 이는 알려진 한계로 기록한다.
- **ADR-4 새 프로젝트 기동:** `agent launch` 대신 `terminal create --command "claude --permission-mode plan --session-id <UUID> -n <slug>"`로 TUI를 보장한다. JARVIS가 만든 세션은 UUID를 알기 때문에 재연결 키로 쓸 수 있다.
- **ADR-5 데이터 위치:** 설정·매핑·체크포인트는 JSON 파일로 저장한다(UserDefaults는 쓰지 않는다). 기본 위치는 `~/Library/Application Support/<bundle-id>/`이고, 개발·테스트 중에는 `JARVIS_DATA_DIR=<프로젝트>/.local-data`로 덮어써 폴더 밖 쓰기를 피한다. 마이크 TCC 항목만은 OS가 기록하는 것이라 피할 수 없다. 로그인 시 실행(SMAppService)은 구현만 하고, 작가님 승인 없이 켜지 않는다.

## 3. 아키텍처와 파일 구조

UI는 CLI를 직접 부르지 않는다. 외부 연동 4개(`OrcaAdapter`, `SpeechRecognizer`, `LocalLLM`, `SkillCatalog`)는 프로토콜로 두고, 테스트에서는 fake를 주입한다.

```
jarvis-launcher/
├── Package.swift                 # swift-tools 6.x, macOS 14+, targets: JARVISCore(lib), JARVISLauncher(exe), JARVISCoreTests
├── Sources/JARVISCore/           # 순수 로직 — UI 의존 없음, swift test 대상
│   ├── Models/        ProjectRecord, TerminalCandidate, Binding, IntentResult, SkillEntry, CreationCheckpoint
│   ├── Process/       CLIProcessRunner (실행파일 URL+인자 배열, 타임아웃, stdout 크기 제한, stderr 마스킹)
│   ├── Orca/          OrcaAdapter(프로토콜), OrcaCLIAdapter, OrcaJSON(Decodable)
│   ├── Sessions/      SessionRegistry (재연결 알고리즘), Fingerprint
│   ├── Dispatch/      DispatchCoordinator (재검증 → 직렬 1회 전송 → 결과 상태), SendGuard
│   ├── Brain/         IntentRouter (규칙 우선 → LLM, 후보 allowlist), PromptComposer (템플릿 폴백), LocalLLM(프로토콜), LlamaServerLLM
│   ├── Speech/        SpeechRecognizer(프로토콜), WhisperCLIRecognizer
│   ├── Projects/      FolderSafety (realpath·..·symlink·중복·권한), ProjectCreationCoordinator (단계 체크포인트, 멱등)
│   ├── Skills/        SkillCatalog (파일 스캔 + orca skills installed 병합, 충돌 감지)
│   └── Storage/       JSONStore, PreferencesStore, ProjectBindingStore
├── Sources/JARVISLauncher/       # AppKit/SwiftUI 셸
│   ├── App/           JARVISLauncherApp (MenuBarExtra), AppCoordinator (상태 머신 PRD 4.7)
│   ├── Hotkey/        GlobalHotkey (Carbon RegisterEventHotKey — 접근성 권한 불필요)
│   ├── Panel/         PromptPanel(NSPanel nonactivating, canBecomeKey), PanelController(포인터 화면 visibleFrame 중앙, 전 Space·전체화면)
│   ├── Views/         PromptView, ConfirmExistingView, ConfirmNewProjectView, SkillPickerView, SettingsView(일반/프로젝트/모델/진단)
│   └── Audio/         MicRecorder (AVAudioEngine → 16k WAV)
├── Resources/Info.plist
├── Tests/JARVISCoreTests/        # Swift Testing; Fixtures/ = 실측 JSON 구조를 익명화한 픽스처
├── scripts/  build-app.sh, fetch-models.sh(승인 후 실행, SHA256 검증), run-dev.sh(JARVIS_DATA_DIR 설정)
├── docs/     02-plan.md, orca-cli-contract.md, adr/, model-benchmarks.md, manual-acceptance-tests.md, known-limitations.md
├── qa/evidence/<AC-xx>/          # 명령 출력, 테스트 로그, 스크린샷
├── .local-models/ .local-data/ build/   # .gitignore
└── README.md
```

**세션 매칭 키**는 `executionHostId + realpath(worktreePath) + worktreeId + agentIdentity`이고, JARVIS가 만든 세션이면 `claudeSessionId`를 더한다. `handle`과 `incarnationId`는 런타임 값으로만 취급한다.

**전송 직전 재검증(SendGuard)**은 `terminal show`로 다음을 모두 확인한다. `handle`이 존재할 것, 확인 화면에 띄운 `incarnationId`와 `worktreePath`(realpath)·`executionHostId == local`이 같을 것, `agentIdentity == claude`, `connected && writable && !orphaned`. 그다음 `terminal read --screen`으로 권한 대화상자·질문 대기 화면이 아닌지 검사한다. 이 검사는 휴리스틱이어서 확실하지 않으면 차단한다. 하나라도 실패하면 전송 0회. 전송은 `send --text --enter --wait-submit 5 --json` 한 번이며, receipt를 `전송 확인 / 상태 불명 / 실패`로 매핑한다. 자동 재시도는 하지 않는다. 수동 재시도는 같은 `--retry-request` ID로만 허용한다.

## 4. 마일스톤

| M | 내용 | 산출물·종료 조건 |
|---|---|---|
| **M0a** | 승인 직후: 이 계획을 `docs/02-plan.md`에 옮기고, `docs/orca-cli-contract.md`와 `docs/adr/`을 작성하고, Spike 0 원문 출력을 `qa/evidence/spike0/`에 둔다(개인 경로·제목은 마스킹) | 문서 커밋 |
| **M0b** | 쓰기 계약 실증: `qa/sandbox/jl-spike-<ts>/` 폴더 → `repo add` → `terminal create --command "claude --permission-mode plan …"` → `wait tui-idle` → `read --screen`으로 플랜 모드 확인 → 테스트 문자열 `send` 1회 → receipt 기록 → 테스트 터미널 close. **기존 세션에는 보내지 않는다** | 계약서에 쓰기 명령 receipt 기록. G0/G1 판정. 실패하면 blocker로 보고하고 멈춘다 |
| **M1** | Package·번들 스크립트, 메뉴바, 전역 핫키(⌃⌥Space, 충돌 안내), 반투명 패널, 텍스트 입력(⌘↵, 빈 입력 차단, 8,000자 경고), 설정 뼈대 | 앱 실행·핫키 30회 확인. AC-01~03 |
| **M2** | CLIProcessRunner, OrcaCLIAdapter, SessionRegistry·재연결, 설정 > 프로젝트 페어링 UI, 수동 대상 선택, DispatchCoordinator·SendGuard | fake 픽스처 테스트 + 테스트 터미널 실제 전송. AC-07~10, 13~15 |
| **M3** | (보고 후) 모델 다운로드. WhisperCLIRecognizer와 마이크 권한, LlamaServerLLM(JSON 출력·검증·폴백), IntentRouter, PromptComposer, 설정 > 모델·진단 | AC-04~06, 11, 12, 22, 23. 벤치마크 문서 |
| **M4** | ProjectCreationCoordinator: 이름 제안 → FolderSafety → 승인 → mkdir → repo add → terminal create(플랜 모드) → 화면 검증 → 1회 전송 → 매핑 저장. 단계 체크포인트와 `이어하기`. 폴더 등록이 안 되면 수동 등록 안내로 대체 | AC-16~18 |
| **M5** | SkillCatalog(`~/.claude/skills`, 프로젝트 `.claude/skills`, 레거시 `commands`, `orca skills installed` 중 claude provider), 출처·검증 수준 표시, 충돌·미확인이면 차단, 기존 전송 경로 재사용 | AC-19, 20 |
| **M6** | 권한·네트워크 점검, 성능 측정, 수동 E2E, README, known-limitations, AC 결과표 | AC-21, 24, 25. 완료 보고 |

## 5. FR ↔ 구현 매핑

| FR | 구현 위치 | M |
|---|---|---|
| FR-01 상주·핫키 | GlobalHotkey, PanelController, MenuBarExtra | M1 |
| FR-02 텍스트 입력 | PromptView, AppCoordinator(원문 보존) | M1 |
| FR-03 받아쓰기 | MicRecorder, WhisperCLIRecognizer | M3 |
| FR-04 Orca 탐색·페어링 | OrcaCLIAdapter, SettingsView/프로젝트 | M2 |
| FR-05 재연결 | SessionRegistry, ProjectBindingStore | M2 |
| FR-06 분류·추천 | IntentRouter(규칙 → LLM, allowlist) | M3 (M2에서는 규칙만) |
| FR-07 메타 프롬프트 | PromptComposer(+템플릿 폴백) | M3 |
| FR-08 확인·1회 전송 | ConfirmExistingView, DispatchCoordinator, SendGuard | M2 |
| FR-09 새 프로젝트·플랜 모드 | FolderSafety, ProjectCreationCoordinator | M4 |
| FR-10 스킬 | SkillCatalog, SkillPickerView | M5 |
| FR-11 설정·진단 | SettingsView, PreferencesStore, Diagnostics | M1~M3 |
| FR-12 상태 표시 | 메뉴바 아이콘 상태, 패널 상태 라벨 | M2~M3 |

## 6. AC ↔ 검증 방법 (증거: `qa/evidence/AC-xx/`)

표기: **자동** = `swift test`/스크립트, **실기** = 실제 Orca·앱 조작(테스트 터미널), **작가님** = 작가님 참여가 필요한 항목. 수행하지 못하면 그 이유와 함께 `미수행`으로 표시한다.

| AC | 방법 | 비고 |
|---|---|---|
| 01 핫키 30회 | 실기: 스크립트 루프 + 로그(표시·포커스·토글) + 스크린샷 | 충돌 시 안내 화면 |
| 02 창 위치 | 자동: 중앙 계산 단위 테스트 / 실기: 내장 디스플레이, 다크·고대비 | 외장 모니터는 **작가님** |
| 03 입력 보존 | 자동: 왕복 상태 전이 테스트(혼합·경로·여러 줄) | |
| 04 마이크 권한 | 실기: 첫 녹음 허용 경로 / 거부 경로(tccutil은 앱 번들 ID 한정 reset) | |
| 05 받아쓰기 40문장 | **작가님** 녹음 40개 → 스크립트로 CER·RTF·P50/P95 측정 → `model-benchmarks.md` | 녹음이 없으면 TTS로 예비 측정하고 "예비"로 표시 |
| 06 오프라인 | 실기: Wi-Fi 끄고 STT·LLM 동작 / 승인 전 다운로드가 0회인지 | |
| 07 Orca 목록 | 실기: 테스트 폴더 터미널 5개 + 기존 목록 **읽기만**. 미확인 표시 | |
| 08 페어링 재시작 | 실기: 테스트 프로젝트 A/B 바인딩 → 앱 재시작 → 재매칭 로그 | |
| 09 핸들 변경 | 자동: 핸들·incarnation 바뀐 픽스처 / 실기: 테스트 터미널 재생성 | |
| 10 중복 세션 | 자동: 같은 경로 claude 2개, 경로·호스트가 빠진 픽스처 → 차단 | |
| 11 추천 40건 | 자동(fake 목록) + 실모델: 명백 20·모호 20, 정확도 기록 | 합격 수치는 미정(PRD) |
| 12 프롬프트 보존 | 자동: 부정문·경로·숫자 보존 검사, 손상된 LLM 출력 → 템플릿 폴백 | |
| 13 오발송 0회 | 자동: 확인 후 픽스처 경로·호스트 변경 → send 호출 0 (fake 카운터) | |
| 14 정확한 1회 | 실기: 테스트 터미널 1회 전송, 중복 클릭 / 자동: 직렬화 | |
| 15 전송 불명 | 자동: send 타임아웃 fake → `상태 불명`, 재전송 0 | |
| 16 신규 폴더 | 자동: 존재·`../`·symlink·권한 없음 (임시 디렉터리는 `.local-data` 아래) | |
| 17 플랜 모드 | 실기: 샌드박스 부모 폴더에서 전 과정 + 화면 증거 | |
| 18 이어하기 | 자동: 단계 실패 fake → 재시도 시 폴더 재사용, 터미널·전송 중복 0 / 실기 1회 | |
| 19 스킬 조회 | 자동: 테스트 루트에 개인·프로젝트·레거시 1개씩 / 실기: 실제 목록 | "전체 목록" 주장 금지 |
| 20 스킬 호출 | 실기: 테스트 터미널에 프로젝트 스킬 1회 / 자동: 충돌 차단 | |
| 21 권한 최소화 | 실기: 접근성·화면기록·전체디스크 요청 없음, 마이크 거부 후 사용 가능 | |
| 22 개인정보 | 실기: 녹음·원문 영구 저장 0(데이터 폴더 diff), `nettop`/`lsof -i`로 외부 연결 0 | |
| 23 모델 실패 | 실기: 모델 경로를 잘못 지정 → 직접 입력·수동 선택·전송 동작 | 파일 삭제 대신 경로 변경 |
| 24 성능 | 실기: 6.1/6.2 항목 측정, 미달은 미달로 표시 | |
| 25 회귀 E2E | 실기: 앱·Orca 재시작, Claude 종료, 한영 입력 / 절전·복귀, 다중 모니터는 **작가님** | |

## 7. 위험·알려진 한계(초기)

- Claude 세션 ID를 Orca가 노출하지 않는다. 기존 세션에서 같은 경로에 Claude가 둘이면 매번 수동으로 선택해야 한다.
- 입력 가능 상태(권한 대화상자·질문 대기)는 화면 텍스트 휴리스틱으로 판정한다. Claude Code UI가 바뀌면 깨질 수 있으므로, 판정이 애매하면 차단 쪽을 기본으로 한다.
- ad-hoc 서명이라 재빌드하면 마이크 권한을 다시 물을 수 있다.
- 원격 호스트(멕미니, ssh)는 MVP 전송 대상에서 제외한다(목록에는 `미확인/원격`으로 표시).
- 테스트용 Orca 폴더 등록을 해제할 수단이 없을 수 있다(M0b에서 확인).

## 8. 검증 (End-to-end)

1. `swift build && swift test`: 순수 로직·fake CLI 테스트 전부 통과(로그는 `qa/evidence/unit/`)
2. `scripts/build-app.sh && open build/JARVISLauncher.app`(`run-dev.sh`로 `JARVIS_DATA_DIR` 지정)
3. 실기 시나리오 A: 샌드박스 테스트 프로젝트 터미널을 페어링 → 핫키 → 입력 → 추천 → 확인 → `전송 확인` → `orca terminal read --screen`으로 도착 확인
4. 실기 시나리오 B: 샌드박스 부모 폴더 → 새 프로젝트 → 플랜 모드 화면 증거 → 메타 프롬프트 1회 도착
5. 실기 시나리오 C: 스킬 선택 → 테스트 터미널에 호출 문자열 1회
6. AC 결과표(`qa/evidence/README.md`): AC별 PASS / FAIL / 미수행 + 근거 경로. 실패와 미검증은 그대로 적는다
