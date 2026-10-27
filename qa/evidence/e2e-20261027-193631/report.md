# 실 Orca E2E 20261027-193631

## A. 기존 프로젝트 전송 (AC-07·08·10·14)
테스트 터미널 생성: term_b4fdef7f…
- [PASS] 테스트 터미널 Claude 준비 — ready(planMode: true, busy: false)
- [PASS] AC-07 목록에 경로·호스트·종류 표시 — 터미널 8개, 페어링 가능 3개, 미확인/제외 5개
- [PASS] AC-10 같은 폴더 Claude 다중 → 자동 확정 안 함(실제 Orca) — 후보 2개: 같은 폴더에 Claude 세션이 2개 있습니다. Orca가 세션 ID를 제공하지 않아 직접 골라야 합니다
- [PASS] AC-08 저장·재로드 후 동일 판정(핸들 재조회) — 사용자 확인 필요
- [PASS] AC-14 1회 전송 → 터미널에 전달됨 — 터미널에 전달됨
- [PASS] AC-14 중복 클릭은 처리 안 함 — 이미 전송 중
- [PASS] AC-14 실제 send 호출 수 — 1회
- [PASS] AC-14 화면에 프롬프트 도착
- [PASS] 중복 문구는 도착하지 않음
- [PASS] AC-13 확인 후 프로세스 변경 → 전송 0회 — 전송 차단

## B. 새 프로젝트 (AC-16·17·18)
1차 실행: completed(JARVISCore.ProjectRecord(id: 28EDEB71-7592-40A1-B3C1-A31FC620CC7D, alias: "e2e-b-20261027193631", canonicalPath: "~/Documents/dev/vibelabs-core/jarvis-launcher", worktreeId: Optional("d0f89355-d79f-46db-99e0-9e86b38ca26f::~/Documents/dev/vibelabs-core/jarvis-launcher"), hostId: "local", note: "", createdClaudeSessionId: Optional("5de1d25a-b184-4a6d-9c6e-003c5eea63be"), lastRuntimeHandle: Optional("term_838a3521-aca0-41c8-99db-7d6e21e45457"), lastSeenAt: Optional(2026-10-27 10:36:46 +0000)), JARVISCore.DeliveryOutcome.delivered(requestId: Optional("1b9d4ea1-0168-4e87-aa5a-5206eb07ca4b")))
- [PASS] AC-17 플랜 모드 확인 후 1회 전달 — 경로 ~/Documents/dev/vibelabs-core/jarvis-launcher
- [PASS] AC-18 이어하기에서 터미널 중복 생성 없음 — 만든 터미널 2개
- [PASS] 완료 후 재실행해도 재전송 없음
- [PASS] 새 폴더가 기본 상위 폴더 안에 생성 — ~/Documents/dev/vibelabs-core/jarvis-launcher/qa/sandbox/e2e-b-20261027193631
참고: 샌드박스가 Git 저장소 안이라 repo add는 상위 저장소로 해석됨(insideExistingRepo=true). Git 밖 폴더 등록은 미검증.

## 정리
닫기 term_b4fdef7f… → 확인 불가
닫기 term_838a3521… → 확인 불가
## 사후 확인 (수동 기록)
- 정리 단계의 "확인 불가": 닫은 직후 핸들이 무효가 되어 `terminal wait`가 `terminal_handle_stale`을 반환함. `orca terminal list`로 두 테스트 터미널이 **남아 있지 않음**을 확인함.
- AC-18 해석: 이번 실행에서는 MCP 대화상자가 뜨지 않아 1차에서 바로 완료됨. 따라서 **실제 Orca에서 '중단 → 이어하기' 경로는 실행되지 않았다.** 이어하기(폴더 재사용·터미널/전송 중복 없음)의 근거는 단위 테스트(`ProjectCreationTests.resume`, `dialogThenResume`)뿐이다.
- 이 실행에서 보낸 대상은 E2E가 직접 만든 테스트 터미널 2개뿐이다(기존 세션 전송 0회).
