# 개발 중 실제로 나온 결함 기록

재현 → 원인 지점 → 수정 → 재발 방지 확인 순서로 기록한다.

| # | 재현 | 원인 지점 | 수정 | 재발 방지 확인 |
|---|---|---|---|---|
| B1 | "새로운 독서 메모 앱을 만들어보자"가 새 프로젝트로 분류되지 않음 | `IntentRouter.newProjectCues`가 붙어 있는 구절("새로운 앱")만 찾음 | '새/신규' 표현 + '만들/시작' 표현의 조합 규칙(`looksLikeNewProject`) 추가 | `BrainTests.ruleNew` 통과 |
| B2 | 원문 "로그인은 만들지 마"의 금지 조건이 정리본에서 빠져도 경고가 없음 | `PromptComposer` 부정 표현 목록에 '-지 마' 형태가 없음 | 정규식 `지\s*(마\|말)` 추가(`hasNegation`) | `BrainTests.composer` 통과 |
| B3 | Xcode 없는 환경에서 `swift test`가 빌드만 하고 테스트를 0개 실행 | CLT에 xctest 러너가 없음(`xcrun --find xctest` 실패) | Swift Testing 진입점을 직접 부르는 실행 타깃 `JARVISCoreTestRunner` | 35개 테스트 실행 로그(`qa/evidence/unit/`) |
| B4 | `run-dev.sh`에서 `open: unrecognized option '--env JARVIS_DEV_HOOKS=1'` | zsh가 `${VAR:+…}` 확장을 한 단어로 넘김 | 인자를 배열로 구성 | 재실행 성공 |
| B5 | 패널 표시 직후 로그가 `key=false` | 표시 직후에는 키 윈도우가 아직 확정되지 않음 | 0.4초 뒤 `panel.focus … textInputFocused=` 로그 추가. 접근성 트리로 포커스가 입력 칸에 있음을 확인 | AC-01 수동 집계에서 확인 |
| B6 | E2E 정리 단계가 "확인 불가" | 닫은 직후 핸들이 무효(`terminal_handle_stale`)가 되어 `wait --for exit`가 실패 | 결과 해석을 보고서에 기록. 실제로 닫혔는지는 `terminal list`로 확인 | e2e 보고서 사후 확인 절 |

참고: AC-01 자동 반복 스크립트는 작가님 화면에서 패널을 깜박이게 해서 폐기했다. AC-01은 작가님이 직접 누른 기록을 집계해 검증한다.
