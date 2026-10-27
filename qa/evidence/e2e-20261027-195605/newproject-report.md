# 새 프로젝트 실연동 (AC-16·17·18)

- 테스트 상위 폴더: ~/Documents/dev/jarvis-launcher-test-parent
- [PASS] AC-16 상위 탈출 이름 거부
1차 실행: stopped(JARVISCore.CreationStep.orca, "Orca는 Git 저장소만 등록할 수 있습니다. \'Git 초기화 후 등록\'을 승인하거나, Orca에서 폴더를 직접 연 뒤 이어하기를 눌러 주세요", canResume: true)
- [PASS] 1차: Git 아님 → 승인 전 정지, 터미널·전송 0회 — Orca는 Git 저장소만 등록할 수 있습니다. 'Git 초기화 후 등록'을 승인하거나, Orca에서 폴더를 직접 연 뒤 이어하기를 눌러 주세요
- [PASS] AC-16 폴더가 상위 폴더 안에 생성 — ~/Documents/dev/jarvis-launcher-test-parent/jl-np-98565
- [PASS] 승인 전에는 git init 하지 않음
2차(승인 후 이어하기): stopped(JARVISCore.CreationStep.claudeReady, "Claude가 확인을 기다리고 있습니다: Enter to confirm · Esc to cancel. Orca에서 직접 처리한 뒤 이어하기를 눌러 주세요", canResume: true)
3차(대화상자 처리 후 이어하기): stopped(JARVISCore.CreationStep.claudeReady, "Claude가 확인을 기다리고 있습니다: Enter to confirm · Esc to cancel. Orca에서 직접 처리한 뒤 이어하기를 눌러 주세요", canResume: true)
- [PASS] Git 밖 폴더가 승인된 git init 후 자기 경로로 등록 — worktreeRoot=~/Documents/dev/jarvis-launcher-test-parent/jl-np-98565
- [FAIL] AC-17 플랜 모드 확인 후 1회 전달 — stopped(JARVISCore.CreationStep.claudeReady, "Claude가 확인을 기다리고 있습니다: Enter to confirm · Esc to cancel. Orca에서 직접 처리한 뒤 이어하기를 눌러 주세요", canResume: true)
- [PASS] AC-18 이어하기 후 새 터미널 정확히 1개(중복 없음) — 1개
- [FAIL] 화면에 메타 프롬프트 도착
- [FAIL] 화면에 플랜 모드 표시
- [FAIL] 완료 후 재실행해도 재전송 없음
- [PASS] AC-16 이미 있는 폴더 거부(덮어쓰지 않음)
테스트 터미널 정리: 닫힘 확인
해제 대상 setup: 1개 (이 시나리오가 등록한 경로만)
Orca 등록 해제(ae77ccf1…): 완료
해제 후 repo 목록 잔존: 없음
테스트 폴더는 남겨 둠: ~/Documents/dev/jarvis-launcher-test-parent/jl-np-98565