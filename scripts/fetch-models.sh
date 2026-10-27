#!/bin/zsh
# 작가님 승인 후에만 실행한다. 근거: docs/model-download-plan.md
# 사용: scripts/fetch-models.sh q4|q8
set -euo pipefail
cd "$(dirname "$0")/.."
VARIANT="${1:-}"
[[ "$VARIANT" == "q4" || "$VARIANT" == "q8" ]] || { echo "usage: $0 q4|q8"; exit 2; }
DEST=.local-models
mkdir -p "$DEST"

fetch() {  # url file sha256
  local url=$1 file=$2 sha=$3
  if [[ -f "$file" ]] && [[ "$(shasum -a 256 "$file" | cut -d' ' -f1)" == "$sha" ]]; then echo "ok (cached): $file"; return; fi
  curl -fL --retry 2 -o "$file.part" "$url"
  local got; got=$(shasum -a 256 "$file.part" | cut -d' ' -f1)
  if [[ "$got" != "$sha" ]]; then rm -f "$file.part"; echo "SHA256 mismatch for $file: $got"; exit 1; fi
  mv "$file.part" "$file"; echo "ok: $file"
}

LLAMA_TAG=b11606
fetch "https://github.com/ggml-org/llama.cpp/releases/download/$LLAMA_TAG/llama-$LLAMA_TAG-bin-macos-arm64.tar.gz" \
  "$DEST/llama-$LLAMA_TAG.tar.gz" a39c5a9c4bbb5b989ed9274300629d5feb5920e52c3257a8e615f3868db44f35
rm -rf "$DEST/llama-$LLAMA_TAG"; mkdir -p "$DEST/llama-$LLAMA_TAG"
tar -xzf "$DEST/llama-$LLAMA_TAG.tar.gz" -C "$DEST/llama-$LLAMA_TAG"

if [[ "$VARIANT" == "q4" ]]; then
  fetch https://huggingface.co/unsloth/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-Q4_K_M.gguf \
    "$DEST/Qwen3-1.7B-Q4_K_M.gguf" b139949c5bd74937ad8ed8c8cf3d9ffb1e99c866c823204dc42c0d91fa181897
else
  fetch https://huggingface.co/Qwen/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-Q8_0.gguf \
    "$DEST/Qwen3-1.7B-Q8_0.gguf" 061b54daade076b5d3362dac252678d17da8c68f07560be70818cace6590cb1a
fi
echo "llama-server: $(find "$DEST/llama-$LLAMA_TAG" -name llama-server -type f | head -1)"
