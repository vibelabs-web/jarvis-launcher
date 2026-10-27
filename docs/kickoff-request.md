[JARVIS REQUEST]
request_id: gb-20261027185600-jl01
mission_id: NEW (JARVIS Launcher)
source: grokbot (vibelabs-dev-orchestrator Gate 3)
target_session: jarvis-launcher (새 프로젝트, 플랜 모드)
user_original: |
  (작가님 요청 요약) 맥OS에 항상 상주하는 앱. 핫키를 누르면 화면 가운데 반투명 프롬프트 창이 뜨고, 마이크로 말하면 가벼운 로컬 모델이 한국어로 받아 적는다.
  요청을 Orca에서 실행 중인 Claude Code 세션으로 보낸다. 설정에서 Orca의 활성 터미널 세션들을 불러와 페어링하고, 앱 시작마다 재연결한다.
  기존 프로젝트면 그 세션으로, 신규 프로젝트면 말한 내용을 메타 프롬프트로 구조화해 새 터미널에서 Claude Code를 플랜 모드로 시작한다. 설치된 스킬 목록도 보여주고 호출할 수 있게.
  작가님 결정: 앱이 세션을 자동 추천 → 작가님 확인 후 전송 / 판단은 로컬 경량 모델 / macOS 전용 Swift로 가장 맥답게 / 첫 버전은 핫키만(음성 호출은 다음 버전) / 새 프로젝트 폴더는 설정의 기본 상위 폴더 + 앱이 이름 제안 → 확인.
task_list:
  1. docs/00-intent.md(작가님과 합의한 의도)와 docs/01-prd.md(ChatGPT가 쓴 PRD, 작가님 승인 완료)를 끝까지 읽는다. PRD가 범위의 기준이다.
  2. 플랜 모드에서 구현 계획을 docs/02-plan.md로 작성한다. 마일스톤, 파일 구조, 각 FR(FR-01~12)과 AC(AC-01~25) 매핑, 검증 방법 포함.
  3. 계획 전에 PRD 5.5·7.3·9.3의 사전 확인 항목을 실제 환경에서 확인한다: Orca CLI 실제 명령(`orca --help`, `orca agent-context`, `orca terminal list/read/send/create --help`), Claude Code 플랜 모드 시작 방법(`claude --help`), WhisperKit 모델 패키징, 설치된 Whisper 호환 여부. 명령과 옵션은 추측하지 말고 --help 결과로만 쓴다.
  4. 받아쓰기 모델(WhisperKit + Whisper small 다국어, 대안 Qwen3-ASR-0.6B·SenseVoiceSmall)과 로컬 LLM(Qwen3-1.7B Q4_K_M via llama.cpp, 대안 EXAONE 4.0 1.2B는 라이선스 주의) 선택안을 계획에 반영한다.
  5. 계획 승인 후 구현: Swift/SwiftUI + AppKit, 메뉴바 상주, 전역 핫키, 가운데 반투명 패널, 마이크 받아쓰기, Orca 세션 페어링·재연결, 세션 추천 → 확인 → 1회 전송, 새 프로젝트 메타 프롬프트 → 폴더 확인 → 새 Orca 터미널에서 Claude 플랜 모드 시작, 스킬 목록 조회·호출.
  6. 검증: 각 AC의 실제 검증 결과(명령 출력, 테스트, 스크린샷 경로)를 qa/evidence/에 남기고, 못 한 항목은 솔직히 표시.
  확인 필요:
  - 모델 파일 다운로드 용량·위치(대용량이면 계획에 적고 진행 전 보고)
  - 개발용 코드 서명/공증은 MVP에서 로컬 실행 기준으로 할지
  완료 기준: 로컬에서 빌드·실행되는 앱, 실행 방법 README, AC별 검증 결과와 근거, 알려진 한계 목록.
desired_action: plan
constraints:
  - 이 프로젝트 폴더 밖 파일 수정·삭제 금지. 기존 Orca 세션에 테스트로 실제 메시지를 보내지 말 것(테스트는 전용 테스트 터미널로).
  - 외부 API·유료 서비스 사용 금지, 원격 push·배포·공개 금지.
  - 비밀키·개인정보를 코드·로그·문서에 넣지 말 것.
  - 통신 오류나 미검증을 성공으로 포장하지 말 것.
[/JARVIS REQUEST]
