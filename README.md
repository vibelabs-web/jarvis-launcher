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

| 동작 | 키 |
|---|---|
| 패널 열기/닫기 | `⌃⌥Space` (설정에서 변경) |
| 다음 단계 / 전송 | `⌘↵` |
| 닫기(입력은 유지) | `Esc` |

- **기존 프로젝트:** 추천 대상의 경로·호스트·터미널을 확인하고, 필요하면 내용을 고친 뒤 **전송**합니다. 전송 직전에 대상을 다시 조회하며, 폴더·호스트·프로세스가 바뀌었거나 Claude가 질문·권한 대화상자를 띄우고 있으면 보내지 않습니다.
- **새 프로젝트:** 폴더 이름과 메타 프롬프트를 확인하고 **폴더/터미널 생성 후 전달**을 누릅니다. 도중에 멈추면(예: Claude의 MCP 승인 대화상자) Orca에서 직접 처리한 뒤 **여기서 이어하기**를 누릅니다. 이어하기는 폴더·터미널을 다시 만들지 않고, 이미 보낸 프롬프트도 다시 보내지 않습니다.
- **스킬:** 목록에서 고르고 인자를 넣은 뒤, 대상 세션으로 호출 문자열을 보냅니다. 이름이 충돌하는 스킬은 막히고, Orca 목록에만 있는 플러그인 스킬은 직접 확인하겠다고 체크해야 보낼 수 있습니다.
- 결과 표시는 `터미널에 전달됨`(Claude가 처리를 시작한 것까지 관찰됨), `전송 여부 불명`(자동으로 다시 보내지 않음), `전송 차단`(0회 전송) 셋으로 나뉩니다.

## 테스트

```sh
swift run JARVISCoreTestRunner   # 단위·fake CLI 테스트 (Swift Testing)
swift run JARVISE2E              # 실제 Orca E2E: 자신이 만든 테스트 터미널에만 전송하고 끝나면 닫음
python3 -I qa/scripts/ac01-tally.py   # 수동 핫키 기록 집계(AC-01)
```

Xcode가 없는 환경에서는 `swift test`가 테스트를 실행하지 않습니다(xctest 러너 없음). 그래서 실행 타깃으로 돌립니다.

## 개인정보

- 음성은 임시 WAV로만 쓰고 전사 직후 지웁니다. 프롬프트 원문은 디스크에 저장하지 않습니다.
- 받아쓰기와 판단 엔진은 로컬에서만 동작하며, 외부 API를 호출하지 않습니다(LLM 서버는 127.0.0.1, 무작위 포트·키).
- 접근성·화면 기록·전체 디스크 접근 권한을 요청하지 않습니다. 마이크 권한은 받아쓰기 버튼을 처음 누를 때만 묻습니다.
