# Orca / Claude Code CLI 계약서 (Spike 0 실증)

- 실증일: 2026-10-27 · Orca CLI **1.4.242** · Claude Code **2.1.311** · macOS 26.5.2 (M1 Pro)
- 근거 원문: `qa/evidence/spike0/` (개인 경로·제목·기기명 마스킹)
- 명령·옵션의 근거는 `orca --help`(01)와 `orca agent-context --json`(03)뿐이다. 이 버전에서는 하위 명령 `--help`가 동작하지 않는다(02, `Unknown command`).
- JARVIS는 아래에 **검증됨**으로 표시된 명령만 호출한다. 버전이 바뀌면 이 문서를 다시 실증한다.

## 1. 공통 규칙

- 실행: `Process`에 실행 파일 URL과 인자 배열을 넘긴다. 셸 문자열 보간은 하지 않는다. 항상 `--json`을 붙인다.
- 응답 봉투: `{ id, ok, result, _meta{runtimeId} }`. `ok != true`이거나 종료 코드가 0이 아니면 실패로 본다.
- Orca 실행 파일 탐색 순서: 설정값 → `/Applications/Orca.app/Contents/Resources/bin/orca` → PATH.

## 2. 읽기 명령 (검증됨)

| 용도 | 명령 | JARVIS가 쓰는 필드 | 증거 |
|---|---|---|---|
| 런타임 상태 | `orca status --json` | `result.app.running`, `result.runtime.state`(`ready`), `runtime.appVersion` | 04-status |
| 호스트 | `orca host list --json` | `hosts[].kind/id`. local id = `local` | 04-hosts |
| 터미널 목록 | `orca terminal list --json` | `terminals[].handle, incarnationId, orphaned, worktreeId, worktreePath, connected, writable, executionHostId, agentIdentity, lastOutputAt` + `hostScope.omittedHostIds` | 04-tl |
| 터미널 단건 | `orca terminal show --terminal <h> --json` | 위 필드 + `agentWait` | m0b-09 |
| 화면 읽기 | `orca terminal read --terminal <h> --screen --json` | `result.terminal.source`(`screen`), `tail[]` | 06, m0b-04/06/08 |
| 대기 | `orca terminal wait --terminal <h> --for tui-idle\|exit --timeout-ms <ms> --json` | `wait.satisfied, status, exitCode, exitCause.kind` | m0b-03, close 확인 |
| 스킬 | `orca skills installed --json` | `skills[].id, name, description, providers[], sourceKind, sourceLabel` | 04-skills |
| 저장소 | `orca repo list --json` | `repos[].id, path, kind(git\|folder)` | 04-repos |

### 식별 가능성 (PRD 9.3-1)
- 경로·호스트: **식별 가능**. `worktreePath`, `executionHostId`를 쓴다.
- 에이전트 종류: `agentIdentity`는 **신뢰할 수 없다**. 실제로 Claude Code가 돌고 있는 터미널 상당수가 null로 오고, 같은 터미널이 `claude`에서 null로 바뀌기도 했다(2026-10-27 실측). 값이 비면 `terminal read --screen`으로 Claude TUI(❯ 프롬프트 + 상태줄 문구)를 판별한다(B14).
- **Claude 세션 ID: 제공되지 않는다.** 같은 worktree에 Claude가 두 개 이상이면 자동으로 매칭하지 않고 매번 수동으로 선택하게 한다.
- `worktreePath`는 **worktree 루트**다. 그 하위 폴더에서 `cd`로 시작한 세션도 루트 경로로 보고된다(m0b-09).
- `orphaned: true`(Orca 탭과 분리) 터미널도 `connected·writable`이고 화면이 Claude면 전송할 수 있다(실측 2개). 다만 Orca 화면에서 바로 보이지 않을 수 있어 앱에 경고를 표시한다.
- 원격 호스트는 `hostScope.omittedHostIds`에 나온다. MVP에서는 `executionHostId == "local"`인 터미널에만 보낸다.

## 3. 쓰기 명령 (실증 결과)

### 3.1 텍스트 전송 — **검증됨** (테스트 전용 터미널, m0b-07)
`orca terminal send --terminal <h> --text <text> --enter --wait-submit <s> --json`

```
result.send.accepted: true
result.send.prompt.requestId: <uuid>
result.send.prompt.stages: ["input_accepted", "turn_started"]
result.send.prompt.provider: "claude", observation: "supported"
result.send.prompt.processIncarnation: <incarnationId와 같음>
result.mutation.replayed: false
```
JARVIS의 결과 매핑:
- `stages`에 `turn_started`가 있으면 **전송 확인**(`터미널에 전달됨`)
- `input_accepted`만 있으면 **상태 불명**
- `accepted:false`이거나 `ok:false`이면 **실패**
- 자동 재전송은 하지 않는다. 사용자가 수동으로 재시도할 때만 `--retry-request <requestId>`로 같은 요청을 재개한다(같은 payload와 incarnation에 묶여 있음).
- `processIncarnation`이 확인 화면의 `incarnationId`와 다르면 이상 징후로 기록한다.

### 3.2 터미널 생성 — **검증됨** (m0b-02)
`orca terminal create --worktree path:<worktree-root> --title <t> --command <text> --json`
→ `result.terminal.{handle, incarnationId, worktreeId, executionHostId, processId, surface}`.
`--command` 문자열은 **로그인 셸에 그대로 입력된다**. 따라서 경로는 작은따옴표로 이스케이프한다(`'` → `'\''`).

### 3.3 터미널 닫기 — **검증됨** (m0b-10)
`orca terminal close --terminal <h> --tab --json` → `ptyKilled:false`가 즉시 반환된다. 닫기는 비동기이므로 `terminal wait --for exit`로 `exitCause.kind == operator_close`를 확인해야 한다.

### 3.4 폴더 등록 — **검증됨(제약 있음)**
`orca repo add --path <dir> --json`
- **Git 저장소 하위 폴더**: 새로 등록하지 않고 **상위 Git 저장소 레코드를 반환**한다(m0b-01).
- **Git이 아닌 빈 폴더**: `Not a valid git repository`로 **거부된다**(`qa/evidence/e2e-20261027-195922/newproject-report.md`). CLI로 대신할 수 있는 경로를 찾지 못했다. `project setup-existing-folder --kind folder`는 `Imported folder does not match the selected project identity`, `terminal create --worktree path:<미등록 폴더>`와 `agent launch`는 `selector_not_found`였다.
- JARVIS의 대응(PRD FR-09): 등록 단계에서 멈추고 **사용자가 'Git 초기화 후 등록'을 따로 승인**하면 `git init` → `repo add`. 또는 사용자가 Orca UI에서 폴더를 직접 열면, 이어하기 때 `repo list`에서 그 경로를 찾아 재사용한다.
- Git 초기화 후 등록하면 worktree 루트가 그 폴더 자체가 된다(실측).
- 정리: `orca project setup-delete --setup <id> --force` — 이 명령으로 테스트 등록을 해제하고 `repo list`에서 사라진 것을 확인했다.

### 3.5 사용하지 않는 명령
- `orca agent launch`: Chat UI 설정에 따라 구조화 채팅으로 열릴 수 있다(스키마 노트). PRD는 TUI를 요구하므로 쓰지 않는다.
- `orca computer *`(UI 자동화): PRD 5.5 절대 규칙에 따라 쓰지 않는다.

## 4. Claude Code 기동 계약 (G1) — **검증됨**

- 플래그(05-claude-help): `--permission-mode plan`, `--session-id <uuid>`, `-n/--name <name>`
- JARVIS가 쓰는 기동 명령: `cd -- '<dir>' && claude --permission-mode plan --session-id <uuid> -n <slug>`
- 플랜 모드 확인: `terminal read --screen`의 `tail`에 `plan mode on`이 있는 줄(m0b-06: `⏸ plan mode on (shift+tab to cycle)`)
- 입력 가능 상태: 화면에 `❯` 프롬프트 줄이 있고, 아래 **차단 패턴**이 없어야 한다.

### 4.0 새 폴더 기동 시 실제로 나온 대화상자 (실측, `qa/evidence/e2e-20261027-195922/newproject-report.md`)
1. **폴더 신뢰**: "Quick safety check: Is this a project you created or one you trust? … ❯ No, exit / Yes, I trust this folder · Enter to confirm · Esc to cancel". **기본 선택이 "No, exit"이다.** Enter만 누르면 Claude가 종료된다.
2. **MCP 승인**: "3 new MCP servers found in this project … Esc to reject all".
JARVIS는 둘 다 자동으로 응답하지 않고 `사용자 확인 필요`로 멈춘다. Claude가 종료되어 셸로 돌아오면 `Claude 종료됨`으로 멈추고, 이어하기 때 같은 터미널에서 1회 다시 시작한다.

### 4.1 중요: `tui-idle`은 입력 가능 상태를 뜻하지 않는다 (m0b-03, m0b-04)
기동 직후 Claude가 **"3 new MCP servers found in this project … Enable selected / Esc to reject all"** 대화상자를 띄운 상태에서도 `terminal wait --for tui-idle`이 `satisfied: true`를 반환했다.
- JARVIS는 대화상자(MCP 승인, 폴더 신뢰, 권한 요청, 질문)에 **자동으로 응답하지 않는다.** 대화상자가 보이면 `사용자 확인 필요` 상태로 멈추고 `Orca에서 열기` / `다시 확인`을 안내한다.
- 차단 패턴(휴리스틱, 버전 의존): `Enable selected`, `Esc to reject`, `Do you trust`, `Yes, proceed`, `Do you want to`, `❯ 1.`. 판정이 애매하면 차단한다.
- M0b 테스트 터미널에서는 이 대화상자를 Esc(모두 거부)로 닫고 진행했다(m0b-05). 활성화한 MCP는 없다.

## 5. 버전 의존 위험
- 화면 패턴(`plan mode on`, 대화상자 문구)은 Claude Code 2.1.311 기준이다. 업데이트되면 회귀 테스트(`Tests/…/ScreenClassifierTests`) 픽스처를 다시 채취한다.
- 하위 명령 `--help`가 동작하지 않으므로 버전이 바뀌면 `agent-context --json`을 다시 채취해 비교한다.
