# AC별 검증 결과 (2026-10-27 기준, 진행 중)

판정: **PASS**(근거 있음) · **부분**(일부만 근거) · **미수행**(아직 안 함/할 수 없음). 미검증 항목은 PASS로 적지 않는다.
근거: 단위 = `unit/test-run-20261027-200057.log` (42/42 통과) · 실 Orca E2E = `e2e-20261027-193631/report.md` · 계약 실증 = `spike0/`

| AC | 판정 | 근거 | 메모 |
|---|---|---|---|
| 01 핫키 30회 | 부분 | `AC-01/manual-hotkey-tally-*.md`(작가님 수동) | 키 이벤트 주입 없이 작가님 입력만 집계. 30회 미만이면 부분 |
| 02 창 위치 | 부분 | 단위 `geometry` + 진단 로그 `insideVisibleFrame=true`(외장 화면) | 내장 화면, 다크·고대비는 수동 확인 필요 |
| 03 입력 보존 | PASS(로직) | 단위 `composerSession` | UI 수동 확인 미수행 |
| 04 마이크 권한 | 준비됨(작가님 대기) | `AC-04/tcc-reset.md`(이 앱만 초기화 성공) | 받아쓰기 버튼을 누르면 권한 대화상자가 뜸 → 작가님 허용/거부 후 진단 로그 `mic.permission` 집계 |
| 05 받아쓰기 40문장 | 부분 | `docs/model-benchmarks.md`(예비: TTS 12문장, 앱과 같은 인식기 경로) | 작가님 실제 음성 40문장은 미수행 |
| 06 오프라인 추론 | PASS | `qa/evidence/AC-11/llm-bench-1793098372.md`(sandbox-exec로 외부 네트워크 차단 확인 후 LLM 분류·정리와 STT 동작) | Wi-Fi 끄기 대신 프로세스 단위 차단. 모델 자동 다운로드 코드 없음(받기는 스크립트·승인으로만) |
| 07 Orca 목록 | PASS | E2E A, `spike0/04-tl` | 미확인/분리 터미널은 제외로 표시 |
| 08 페어링 재시작 | 부분 | 단위 `reconnects` + E2E 저장·재로드 | 앱 UI 재시작 시나리오는 수동 확인 필요 |
| 09 핸들 변경 | PASS(로직) | 단위 `handleChanged` | Orca 재시작 실기 미수행 |
| 10 중복 세션 | PASS | 단위 + E2E A(실제 같은 폴더 Claude 2개 → 자동 확정 안 함) | |
| 11 추천 40건 | 측정 완료 | `qa/evidence/AC-11/llm-bench-1793098372.md`: 명백 14/20 정답·6 수동(오답 0), 모호 20/20 안전, P95 3.18s | PRD에 합격률 수치 없음. 가상 후보 6개 기준 |
| 12 프롬프트 보존 | PASS | 단위 + `qa/evidence/AC-11/llm-bench-1793098372.md`(실모델 출력에 원문 포함, 손상 JSON은 템플릿) | 실모델에서 거짓 경고 1건을 발견해 수정(B9) |
| 13 오발송 0회 | PASS | 단위(경로·호스트 변경) + E2E(incarnation 변경 → 차단, send 1회 유지) | |
| 14 정확한 1회 | PASS | E2E A(전달됨, 중복 클릭 차단, send 1회, 화면 도착) | |
| 15 전송 불명 | PASS(로직) | 단위 `timeoutUnknown`, `acceptedOnly` | |
| 16 신규 폴더 | PASS | 단위 `folderSafety` + `qa/evidence/e2e-20261027-195922/newproject-report.md`(Git 밖 실폴더: 탈출·중복 거부, 덮어쓰기 없음) | |
| 17 플랜 모드 | PASS | `qa/evidence/e2e-20261027-195922/newproject-report.md`(Git 밖 새 폴더 → 승인된 git init → 등록 → 플랜 모드 확인 → 1회 전달) + 이전 e2e B | 신뢰·MCP 대화상자는 테스트에서만 대행 응답 |
| 18 이어하기 | PASS | `qa/evidence/e2e-20261027-195922/newproject-report.md`(실 Orca: 승인 대기 중단 → 이어하기, 대화상자 중단 → 이어하기, 새 터미널 1개, 재실행 시 재전송 없음) + 단위 | |
| 19 스킬 조회 | PASS | 단위 `discover` + `qa/evidence/e2e-20261027-194210/skill-report.md`(실제 카탈로그에 프로젝트 스킬 표시) | 전체 목록이라고 주장하지 않음 |
| 20 스킬 호출 | PASS | `qa/evidence/e2e-20261027-194210/skill-report.md`(테스트 터미널에 `/jl-echo` 1회 → 화면에 JL-ECHO-OK) + 단위(충돌 차단) | 패널 UI 경로는 수동 확인 필요 |
| 21 권한 최소화 | 부분 | `AC-21/permissions-code-audit.md`(접근성·화면기록·전체디스크 API 0건) | 마이크 거부 시 동작은 수동 확인 필요 |
| 22 개인정보 | 부분 | `AC-22/privacy-check.md`(유휴 소켓 0, 데이터 폴더에 원문·음성 없음) | 실제 받아쓰기·전송 후 점검, LLM 실행 중 네트워크 점검 미수행 |
| 23 모델 실패 | 부분 | 설계·단위(LLM 없음 → 규칙·템플릿, STT 모델 없음 → 오류 후 텍스트 입력) | 앱 UI에서 모델 경로를 틀리게 두고 확인하는 것은 M6 수동 |
| 24 성능 | 부분 | `AC-24/perf-partial.md`(RSS 115MB, CLI 목록 P95 0.18s, STT 예비) | 핫키 지연, LLM 지연, 동시 메모리 미측정 |
| 25 회귀 E2E | 미수행 | — | 절전·다중 모니터 등은 작가님 참여 |
