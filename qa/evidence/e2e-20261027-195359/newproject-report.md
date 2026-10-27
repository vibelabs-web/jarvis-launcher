# 새 프로젝트 실연동 (AC-16·17·18)

- 테스트 상위 폴더: ~/Documents/dev/jarvis-launcher-test-parent
- [PASS] AC-16 상위 탈출 이름 거부
1차 실행: stopped(JARVISCore.CreationStep.orca, "Orca에 폴더를 등록하지 못했습니다: orca repo add 실패: Not a valid git repository: ~/Documents/dev/jarvis-launcher-test-parent/jl-np-98440. Orca에서 폴더를 직접 연 뒤 이어하기를 눌러 주세요", canResume: true)
- [FAIL] 1차: Claude 준비 전 단계에서 멈추고 전송 0회 — Orca에 폴더를 등록하지 못했습니다: orca repo add 실패: Not a valid git repository: ~/Documents/dev/jarvis-launcher-test-parent/jl-np-98440. Orca에서 폴더를 직접 연 뒤 이어하기를 눌러 주세요
- [PASS] AC-16 폴더가 상위 폴더 안에 생성 — ~/Documents/dev/jarvis-launcher-test-parent/jl-np-98440
- [FAIL] Git 밖 빈 폴더가 Orca에 자기 경로로 등록(L4) — worktreeRoot=-
2차(이어하기): stopped(JARVISCore.CreationStep.orca, "Orca에 폴더를 등록하지 못했습니다: orca repo add 실패: Not a valid git repository: ~/Documents/dev/jarvis-launcher-test-parent/jl-np-98440. Orca에서 폴더를 직접 연 뒤 이어하기를 눌러 주세요", canResume: true)
- [FAIL] AC-17 플랜 모드 확인 후 1회 전달 — stopped(JARVISCore.CreationStep.orca, "Orca에 폴더를 등록하지 못했습니다: orca repo add 실패: Not a valid git repository: ~/Documents/dev/jarvis-launcher-test-parent/jl-np-98440. Orca에서 폴더를 직접 연 뒤 이어하기를 눌러 주세요", canResume: true)
- [PASS] AC-18 이어하기: 같은 터미널 재사용(중복 생성 없음)
- [FAIL] AC-18 새로 생긴 터미널 수 1 — 0개
- [FAIL] 화면에 메타 프롬프트 도착
- [FAIL] 화면에 플랜 모드 표시
- [FAIL] 완료 후 재실행해도 재전송 없음
- [PASS] AC-16 이미 있는 폴더 거부(덮어쓰지 않음)
Orca 등록 해제: 대상 setup을 찾지 못함(수동 확인 필요)
해제 후 repo 목록 잔존: 없음
테스트 폴더는 남겨 둠: ~/Documents/dev/jarvis-launcher-test-parent/jl-np-98440