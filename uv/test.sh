#!/usr/bin/env bash

IMAGE="${1:?usage: $0 <image:tag>}"

BLUE='\033[34m'
RED='\033[31m'
RESET='\033[0m'

VERSIONS=(2.4.1 2.5.1 2.6.0 2.7.1 2.9.0)

for v in "${VERSIONS[@]}"; do
  echo "=== torch ${v} ==="
  if docker run -it --rm --gpus all -e TORCH_VER="$v" "$IMAGE" bash -lc '
    set -euo pipefail
    work="/tmp/torchtest-${TORCH_VER}"
    rm -rf "$work" && mkdir -p "$work" && cd "$work"

    init2="uv_init_torch_${TORCH_VER}"
    init1="uv_init_torch${TORCH_VER}"
    if command -v "$init2" >/dev/null 2>&1; then "$init2"; else "$init1"; fi

    ./.venv/bin/python -c "import importlib, torch; \
ok = torch.cuda.is_available(); assert ok; \
_ = torch.empty(1, device=\"cuda\"); \
importlib.import_module(\"flash_attn\"); \
importlib.import_module(\"triton\")"
  ' >/dev/null; then
    echo -e "${BLUE}OK${RESET}"
  else
    echo -e "${RED}FAIL${RESET}"
  fi
done