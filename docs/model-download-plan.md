# 모델 다운로드 계획 — **승인 대기 (아직 받지 않음)**

조회일: 2026-10-27. Hugging Face·GitHub API로 메타데이터만 조회했다. 저장 위치는 모두 프로젝트 안의 `.local-models/`이며 `.gitignore` 대상이다(ADR-2).

| # | 항목 | URL | 용량 | SHA256 | 저장 위치 |
|---|---|---|---|---|---|
| 1 | llama.cpp `llama-server` (b11606, 2026-10-13 빌드, macOS arm64) | https://github.com/ggml-org/llama.cpp/releases/download/b11606/llama-b11606-bin-macos-arm64.tar.gz | 12,116,141 B (약 11.6MB) | `a39c5a9c4bbb5b989ed9274300629d5feb5920e52c3257a8e615f3868db44f35` (GitHub asset digest) | `.local-models/llama-b11606/` |
| 2a | Qwen3-1.7B **Q4_K_M** GGUF — *제3자 양자화(unsloth)* | https://huggingface.co/unsloth/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-Q4_K_M.gguf | 1,107,409,472 B (약 1.03GiB) | `b139949c5bd74937ad8ed8c8cf3d9ffb1e99c866c823204dc42c0d91fa181897` (LFS oid) | `.local-models/Qwen3-1.7B-Q4_K_M.gguf` |
| 2b | (대안) Qwen3-1.7B **Q8_0** GGUF — *Qwen 공식 저장소* | https://huggingface.co/Qwen/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-Q8_0.gguf | 1,834,426,016 B (약 1.71GiB) | `061b54daade076b5d3362dac252678d17da8c68f07560be70818cace6590cb1a` (LFS oid) | `.local-models/Qwen3-1.7B-Q8_0.gguf` |

**확인한 사실**
- Qwen 공식 GGUF 저장소에는 **Q4_K_M이 없고 Q8_0만** 있다. PRD 기본안(Q4_K_M)을 지키려면 제3자 양자화인 2a를 받아야 하고, 공식 출처를 원하면 2b(약 0.7GB 더 큼)를 받는다. 둘 중 하나만 받으면 된다.
- 최신 llama.cpp 빌드(b119xx)는 오늘(2026-10-27) 나온 prerelease라서, 2주가량 된 b11606에 고정했다.
- 받아쓰기 모델은 추가로 받지 않는다(기존 `~/.cache/whisper-cpp/ggml-small.bin`을 읽기만 함, ADR-1).

**실행 방법 (승인 후):** `scripts/fetch-models.sh q4` 또는 `scripts/fetch-models.sh q8`. 받은 뒤 SHA256이 위 값과 다르면 파일을 지우고 실패로 끝낸다. 압축 해제는 별도 빈 폴더에 하며, 받은 바이너리는 실행 전에 `codesign -dv`와 `--help` 출력으로 확인한다.

**라이선스:** Qwen3 Apache-2.0, llama.cpp MIT. EXAONE(NC)은 받지 않는다.
