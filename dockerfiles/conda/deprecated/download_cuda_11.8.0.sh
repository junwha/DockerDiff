#!/bin/bash
docker pull junwha/dslice-base
../dslice push junwha/dslice-base

for PY_VERSION in 3.8 3.10 3.12; do
    docker pull junwha/dslice-base-py:$PY_VERSION
    ../dslice push junwha/dslice-base-py:$PY_VERSION
done

TORCH_VERSION_PAIRS=(
    "2.4.1 0.19.1"
)
for PY_VERSION in 3.8 3.10 3.12; do
    for TORCH_VERSION_PAIR in "${TORCH_VERSION_PAIRS[@]}"; do
        read -r TORCH_VERSION TORCH_VISION_VERSION <<< "$TORCH_VERSION_PAIR"
        docker pull junwha/dslice-base-torch:py$PY_VERSION-torch$TORCH_VERSION
        ../dslice push junwha/dslice-base-torch:py$PY_VERSION-torch$TORCH_VERSION
    done
done

