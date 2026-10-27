# 실 Orca E2E 20261027-201456

## A. 기존 프로젝트 전송 (AC-07·08·10·14)
테스트 터미널 생성: term_2c99e300…
- [PASS] 테스트 터미널 Claude 준비 — ready(planMode: true, busy: false)
- [PASS] AC-07 목록에 경로·호스트·종류 표시 — 터미널 8개, 페어링 가능 2개, 미확인/제외 6개
- [PASS] AC-10 같은 폴더 Claude 다중 → 자동 확정 안 함(실제 Orca) — 후보 2개: 같은 폴더에 Claude 세션이 2개 있습니다. Orca가 세션 ID를 제공하지 않아 직접 골라야 합니다
- [PASS] AC-08 저장·재로드 후 동일 판정(핸들 재조회) — 사용자 확인 필요
- [PASS] AC-14 1회 전송 → 터미널에 전달됨 — 터미널에 전달됨
- [PASS] AC-14 중복 클릭은 처리 안 함 — 이미 전송 중
- [PASS] AC-14 실제 send 호출 수 — 1회
- [PASS] AC-14 화면에 프롬프트 도착
- [PASS] 중복 문구는 도착하지 않음
- [PASS] AC-13 확인 후 프로세스 변경 → 전송 0회 — 전송 차단

## B. 새 프로젝트 (AC-16·17·18)
1차 실행: completed(JARVISCore.ProjectRecord(id: 160E7B8D-1386-4001-816B-6ACF3DAA1E28, alias: "e2e-b-20261027201456", canonicalPath: "~/Documents/dev/vibelabs-core/jarvis-launcher", worktreeId: Optional("d0f89355-d79f-46db-99e0-9e86b38ca26f::~/Documents/dev/vibelabs-core/jarvis-launcher"), hostId: "local", note: "", createdClaudeSessionId: Optional("028a359b-0a9e-4a99-84c0-fdb6747dd203"), lastRuntimeHandle: Optional("term_13039112-f48d-49a0-b92f-67539878492c"), lastSeenAt: Optional(2026-10-27 11:15:12 +0000)), JARVISCore.DeliveryOutcome.delivered(requestId: Optional("5fd84180-133c-4a8a-ad4f-2f7e5a55b213")))
- [PASS] AC-17 플랜 모드 확인 후 1회 전달 — 경로 ~/Documents/dev/vibelabs-core/jarvis-launcher
- [PASS] AC-18 이어하기에서 터미널 중복 생성 없음 — 만든 터미널 2개
- [PASS] 완료 후 재실행해도 재전송 없음
- [PASS] 새 폴더가 기본 상위 폴더 안에 생성 — ~/Documents/dev/vibelabs-core/jarvis-launcher/qa/sandbox/e2e-b-20261027201456
참고: 샌드박스가 Git 저장소 안이라 repo add는 상위 저장소로 해석됨(insideExistingRepo=true). Git 밖 폴더 등록은 미검증.

## 정리
닫기 term_2c99e300… → exited
닫기 term_13039112… → exited

## 사후 기록
- **의도하지 않은 실행**: 다른 확인 명령에 지우지 못한 `swift run JARVISE2E` 줄이 남아 실행됨(2026-10-27 20:14). 이 E2E가 만든 테스트 터미널 2개에만 보냈고 둘 다 닫힘(exited). 기존 세션 전송 0회. 결과는 참고용으로만 보관.
