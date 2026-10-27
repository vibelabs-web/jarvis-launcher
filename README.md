# JARVIS Launcher (가칭)

macOS 메뉴바에 상주하는 프롬프트 런처. 전역 단축키(기본 `⌃⌥Space`)로 화면 가운데 반투명 패널을 열고, 텍스트나 로컬 받아쓰기로 요청을 입력하면 Orca에서 실행 중인 Claude Code 세션으로 **확인 후 1회** 전달합니다. 새 프로젝트라면 메타 프롬프트를 정리하고 폴더를 만든 뒤, 새 Orca 터미널에서 Claude Code를 플랜 모드로 시작합니다.

- 기획: `docs/00-intent.md`, `docs/01-prd.md` · 계획: `docs/02-plan.md`
- CLI 계약(실측): `docs/orca-cli-contract.md` · 결정 기록: `docs/adr/README.md`
- 검증 결과: `qa/evidence/README.md` · 알려진 한계: `docs/known-limitations.md`

## 요구 환경

- macOS 14 이상, Apple Silicon (개발·검증: macOS 26.5.2, M1 Pro)
- Swift 6 툴체인 (Xcode 없이 Command Line Tools만으로 빌드 가능)
- Orca 1.4.x (`/Applications/Orca.app`) 실행 중 · Claude Code CLI(`claude`)가 Orca 터미널 PATH에 있을 것
- 받아쓰기: `whisper-cli`(brew `whisper-cpp`)와 다국어 모델(기본 `~/.cache/whisper-cpp/ggml-small.bin`)
- 로컬 LLM(선택): `llama-server` + Qwen3-1.7B GGUF. 없으면 규칙·템플릿으로만 동작합니다. 내려받기는 `docs/model-download-plan.md`를 확인한 뒤 `scripts/fetch-models.sh q4|q8`로 합니다.

## 빌드와 실행

```sh
scripts/build-app.sh            # build/JARVISLauncher.app 조립 + ad-hoc 서명
scripts/run-dev.sh              # 데이터를 프로젝트 안 .local-data/ 에 두고 실행
```

일반 실행(`open build/JARVISLauncher.app`)이면 데이터는 `~/Library/Application Support/dev.vibelabs.jarvis-launcher/`에 저장됩니다.

## 처음 설정

1. 메뉴바 아이콘 → **설정…**
2. **프로젝트** 탭: 기본 상위 폴더를 고릅니다. 아래 "Orca 터미널" 표에서 Claude Code 터미널을 **연결**하고, 별칭과 설명을 적어 둡니다(추천에 쓰입니다).
3. **모델** 탭: whisper·llama 경로를 확인합니다. LLM이 없으면 "로컬 LLM 사용"을 끄면 됩니다.
4. **진단** 탭: Orca 상태, 마이크 권한, 데이터 폴더 위치를 확인합니다.

## 쓰는 법

패널은 한 화면입니다. 입력창 아래에 칩이 있습니다(ChatGPT 입력창의 옵션처럼).

```
[ 무엇을 도와드릴까요?  @ 프로젝트 · / 스킬 · ⌘↵ 보내기        ]
  …/vibelabs-obs · 이 Mac · Claude "승인 작업 번거로움…"      ← 보낼 대상 요약
[@ vibelabs-obs 연결됨 ▾ ✕] [🎙]              [/ 스킬 ▾] [↑ 보내기 ⌘↵]
```

| 동작 | 방법 |
|---|---|
| 패널 열기/닫기 | `⌃⌥Space` (설정에서 변경) |
| 프로젝트 고르기 | 왼쪽 `@` 칩, 또는 입력 중 `@이름` → ↑↓·↵ |
| 스킬 고르기 | 오른쪽 `/` 칩, 또는 입력 중 `/이름` → ↑↓·↵ |
| 보내기 | `⌘↵` 또는 보내기 버튼 |
| 닫기(입력은 유지) | `Esc` (목록이 열려 있으면 목록부터 닫음) |
| 입력창 크게 보기 | `⌘E` 또는 입력창 오른쪽 위 확대 버튼 |
| 전체 보기 창 | `⌘⇧E` 또는 입력창 오른쪽 위 창 버튼 (Esc 닫기, ⌘↵ 보내기) |

- **프로젝트 칩:** `@` 목록에 연결된 프로젝트(상태·세션 제목)와 아직 연결하지 않은 Orca Claude 터미널(바로 `연결하기`), `＋ 새 프로젝트`가 나옵니다. 같은 폴더에 Claude가 여러 개면 터미널별로 따로 나옵니다.
- **자동 추천:** 입력에 프로젝트 이름이 있으면 칩이 `추천` 표시와 함께 채워집니다. 마지막으로 보낸 대상은 다음에 `지난 대상`으로 채워집니다. 칩이 비어 있으면 ⌘↵가 먼저 대상을 추천만 하고, 한 번 더 ⌘↵를 눌러야 보냅니다.
- **보내기:** 보내기 직전에 대상을 다시 조회합니다. 폴더·호스트·프로세스가 바뀌었거나 Claude가 질문·권한 대화상자를 띄우고 있으면 보내지 않습니다. 결과는 입력창 아래 한 줄로 표시됩니다(`전달됨` / `전송 여부 불명` — 자동 재전송 없음 / `보내지 않았습니다`).
- **스킬:** 선택한 스킬은 `/스킬 입력내용`으로 보냅니다. 이름이 충돌하는 스킬은 고를 수 없고, Orca 목록에만 있는 스킬(추정)은 보낼 때 한 번 더 확인합니다.
- **새 프로젝트:** `@` → `＋ 새 프로젝트`, 내용 입력 → ⌘↵을 누르면 같은 창에 확인 카드가 펼쳐집니다(폴더 이름·경로·메타 프롬프트). **폴더·터미널 만들고 전달**을 누르면 진행합니다. 새 폴더에서는 Claude의 폴더 신뢰·MCP 승인 대화상자 때문에 한 번 멈추는 것이 보통이니, Orca에서 처리한 뒤 **여기서 이어하기**를 누릅니다. Orca는 Git 저장소만 등록하므로 Git이 아닌 새 폴더는 **Git 초기화 후 등록(승인)**이 필요합니다.
- **받아쓰기:** 🎙 → 말하기(빨간 파형이 움직임) → 다시 🎙. 받아쓴 말은 Claude Haiku 5.5가 **목표·배경·할 일·조건·확인할 점**으로 정리해 커서 위치에 넣고, 끝에 받아쓴 원문을 붙입니다. 바로 보내지 않으니 확인·수정 후 ⌘↵. 결과 줄의 **원문으로 되돌리기**로 받아쓴 그대로 돌아갈 수 있습니다.
- **프롬프트 기록:** Claude Code 훅으로 프롬프트를 SQLite에 남기고, 설정 > **프롬프트 기록**에서 프로젝트·검색·★최초 프롬프트로 골라 마크다운 하나로 내보냅니다. 훅 설치: `scripts/install-prompt-hook.sh`(미리보기) → `--apply`(백업 후 `~/.claude/settings.json`에 항목 추가), 제거는 `--remove`.

## 테스트

```sh
swift run JARVISCoreTestRunner   # 단위·fake CLI 테스트 (Swift Testing)
swift run JARVISE2E              # 실제 Orca E2E: 자신이 만든 테스트 터미널에만 전송하고 끝나면 닫음
python3 -I qa/scripts/ac01-tally.py   # 수동 핫키 기록 집계(AC-01)
```

Xcode가 없는 환경에서는 `swift test`가 테스트를 실행하지 않습니다(xctest 러너 없음). 그래서 실행 타깃으로 돌립니다.

## 개인정보

- 음성은 임시 WAV로만 쓰고 전사 직후 지웁니다.
- 받아쓰기(whisper.cpp)와 프로젝트 추천·메타 프롬프트(로컬 LLM, 127.0.0.1)는 로컬에서 동작합니다.
- **받아쓴 말의 정리는 `claude -p`(Haiku 5.5)로 하므로 Anthropic으로 전송됩니다**(ADR-7, 설정에서 로컬 모델로 바꿀 수 있음).
- **프롬프트 기록을 켜면(훅 설치) Claude Code에 입력한 프롬프트가 `.local-data/prompts.sqlite`에 저장됩니다**(ADR-8). 비밀키처럼 보이는 값은 가려 저장하고, 설정에서 일시 중지·삭제할 수 있습니다.
- 접근성·화면 기록·전체 디스크 접근 권한을 요청하지 않습니다. 마이크 권한은 받아쓰기 버튼을 처음 누를 때만 묻습니다.
