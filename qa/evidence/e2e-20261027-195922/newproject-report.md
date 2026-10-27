# 새 프로젝트 실연동 (AC-16·17·18)

- 테스트 상위 폴더: ~/Documents/dev/jarvis-launcher-test-parent
- [PASS] AC-16 상위 탈출 이름 거부
1차 실행: stopped(JARVISCore.CreationStep.orca, "Orca는 Git 저장소만 등록할 수 있습니다. \'Git 초기화 후 등록\'을 승인하거나, Orca에서 폴더를 직접 연 뒤 이어하기를 눌러 주세요", canResume: true)
- [PASS] 1차: Git 아님 → 승인 전 정지, 터미널·전송 0회 — Orca는 Git 저장소만 등록할 수 있습니다. 'Git 초기화 후 등록'을 승인하거나, Orca에서 폴더를 직접 연 뒤 이어하기를 눌러 주세요
- [PASS] AC-16 폴더가 상위 폴더 안에 생성 — ~/Documents/dev/jarvis-launcher-test-parent/jl-np-98763
- [PASS] 승인 전에는 git init 하지 않음
2차(승인 후 이어하기): stopped(JARVISCore.CreationStep.claudeReady, "Claude가 확인을 기다리고 있습니다: Enter to confirm · Esc to cancel. Orca에서 직접 처리한 뒤 이어하기를 눌러 주세요", canResume: true)
대화상자 원문(trust):
```
─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
 Accessing workspace:
 ~/Documents/dev/jarvis-launcher-test-parent/jl-np-98763
 Quick safety check: Is this a project you created or one you trust? (Like your own code, a well-known open source project, or work from
 your team). If not, take a moment to review what's in this folder first.
 Claude Code'll be able to read, edit, and execute files here.
 Security guide
 ❯ No, exit
   Yes, I trust this folder
 Enter to confirm · Esc to cancel
```
→ 테스트 대행 응답: ↓ + Enter (Yes, I trust this folder — 테스트 폴더 한정)
대화상자 원문(other):
```
-permission-mode plan --session-id 4a8a9e44-2215-42fe-87ac-285bb3d304c1 -n 'jl-np-98763'
─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
  3 new MCP servers found in this project
  Select any you wish to enable.
  MCP servers may execute code or access system resources. All tool calls require approval. Learn more in the MCP documentation.
  ❯ [✔] gemini
    [✔] context7
    [✔] playwright
       Enable selected
 Space to select · Esc to reject all
```
→ 테스트 대행 응답: Esc (모두 거부)
3차(대화상자 처리 후 이어하기): completed(JARVISCore.ProjectRecord(id: 1E51448C-0678-4457-B751-CC028FE53963, alias: "jl-np-98763", canonicalPath: "~/Documents/dev/jarvis-launcher-test-parent/jl-np-98763", worktreeId: Optional("7bac490b-b1d5-4d2d-8888-55d9369c802a::~/Documents/dev/jarvis-launcher-test-parent/jl-np-98763"), hostId: "local", note: "", createdClaudeSessionId: Optional("4a8a9e44-2215-42fe-87ac-285bb3d304c1"), lastRuntimeHandle: Optional("term_ac601b78-6f6b-4558-8058-ecc72a8092b6"), lastSeenAt: Optional(2026-10-27 10:59:33 +0000)), JARVISCore.DeliveryOutcome.delivered(requestId: Optional("e045d848-12c6-47d4-a6fe-481035ba8a77")))
- [PASS] Git 밖 폴더가 승인된 git init 후 자기 경로로 등록 — worktreeRoot=~/Documents/dev/jarvis-launcher-test-parent/jl-np-98763
- [PASS] AC-17 플랜 모드 확인 후 1회 전달 — 경로 ~/Documents/dev/jarvis-launcher-test-parent/jl-np-98763
- [PASS] AC-18 이어하기 후 새 터미널 정확히 1개(중복 없음) — 1개
- [PASS] 화면에 메타 프롬프트 도착
- [FAIL] 화면에 플랜 모드 표시
- [PASS] 완료 후 재실행해도 재전송 없음
- [PASS] AC-16 이미 있는 폴더 거부(덮어쓰지 않음)
테스트 터미널 정리: 닫힘 확인
해제 대상 setup: 1개 (이 시나리오가 등록한 경로만)
Orca 등록 해제(7bac490b…): 완료
해제 후 repo 목록 잔존: 없음
테스트 폴더는 남겨 둠: ~/Documents/dev/jarvis-launcher-test-parent/jl-np-98763
## 사후 확인 (수동 기록)
- "화면에 플랜 모드 표시" FAIL은 **전송 뒤** 화면 검사다. 코디네이터는 화면에서 `plan mode on`을 확인해야만(`planModeVerified=true`) 전송 단계로 간다. 즉 전송 직전 확인은 통과했다. 전송 뒤 Claude가 작업 중일 때 하단 표시가 달라진 것으로 보이나, 원문을 남기지 않아 단정하지 않는다.
- 대화상자 대행 응답은 이 시나리오가 만든 테스트 폴더·테스트 터미널에서만 했다. 앱 자체는 어떤 대화상자에도 자동 응답하지 않는다.
- Orca 등록은 이 시나리오가 만든 1건만 `project setup-delete`로 해제했다. 테스트 폴더(`jl-np-*`)는 테스트 상위 폴더 안에 남겨 두었다.
