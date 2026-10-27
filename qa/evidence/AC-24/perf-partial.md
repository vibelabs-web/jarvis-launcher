# AC-24 성능 측정(일부) 2026-10-27T19:44:11+09:00 — macOS 26.5.2, Apple M1 Pro 32GB
## 앱 메모리(유휴, 모델 미로드)
- RSS 115.1 MB (목표 ≤ 250MB 추가 메모리)
## 앱 시작 → 핫키 등록·Orca 조회 (진단 로그 기준, 마지막 기동)
2026-10-27T10:33:58Z app.launched 
2026-10-27T10:33:59Z orca.refresh terminals=7 projects=0 connected=0
2026-10-27T10:37:12Z hotkey.pressed visible=false
## orca terminal list 지연(10회, 앱과 같은 CLI 호출)
- P50 0.16s / P95(최댓값) 0.18s (목표 P95 ≤ 3s, 터미널 7개)
## 받아쓰기 지연: docs/model-benchmarks.md (예비, TTS 12문장) — small P95 1.14s, turbo P95 2.12s (목표 P95 ≤ 5s, 10초 발화 기준은 미측정)
## 전송 지연: e2e 보고서 기준 성공 1회(--wait-submit 5). 반복 측정 미수행
## 미수행: 핫키→포커스 P95(작가님 수동 확인 때 로그로 측정 예정), LLM 분류 지연(모델 미설치), STT+LLM 동시 메모리
