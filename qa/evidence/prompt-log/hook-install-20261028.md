# 프롬프트 기록 훅 설치·실기 확인 (2026-10-28 01:04~01:07, request gb-20261028010400-hk01)

## 설치
- 승인: 작가님 "훅 설치 승인. 설치하고 시험 터미널로 확인해"
- 백업: `~/.claude/settings.json.bak-jarvis-20261028-010408`
- 백업 대비 변경(`diff`): `hooks.UserPromptSubmit`에 아래 그룹 하나 추가, 그 밖의 줄 변화 없음. 적용 후 JSON 검증 통과.

```diff
>       },
>       {
>         "hooks": [
>           {
>             "type": "command",
>             "command": "<repo>/build/jarvis-prompt-hook --db <repo>/.local-data/prompts.sqlite",
>             "timeout": 5
>           }
>         ]
```

## 실기 확인 (테스트 전용 Orca 터미널)
- 시험 폴더 `.local-data/test-tmp/hook-010538`에서 `claude --permission-mode plan -n jl-hook-test`로 띄운 새 터미널 1개에만 1회 전송.
- 첫 시도는 `--wait-submit` 값 누락으로 Orca가 거부(`invalid_argument`) → 아무것도 보내지 않음. 값을 넣어 다시 1회 전송: stages `input_accepted, turn_started`, Claude 응답 `ok`.
- DB 기록(시험 행): `hook-010538 | JARVIS 훅 기록 시험입니다. ok라고만 답해 주세요. api_key=<masked>`
- 비밀값 원문(`jl-test-secret-…`) 검색 결과 0건 → 저장 전 가림 동작 확인.
- `prompt-hook-errors.log` 없음(오류 0).
- 시험 터미널 닫음(`ptyKilled: true`), 이후 목록에서 사라진 것 확인. 기존 세션에는 보내지 않음.

## 관찰
- 설치 직후 **이미 실행 중이던 이 개발 세션의 다음 입력도 기록됨**(행 1, 내용은 여기 옮기지 않음). 훅 설정은 실행 중인 세션에도 바로 적용된다.
