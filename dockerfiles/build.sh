#!/bin/bash
docker build -t junwha/dslice-base --build-arg DOCKER_CUDA_VERSION=11.8.0 -f Dockerfile.base ./
../dslice push junwha/dslice-base

for PY_VERSION in 3.8 3.10 3.12; do
    docker build -t junwha/dslice-base-py:$PY_VERSION --build-arg PY_VERSION=$PY_VERSION -f Dockerfile.py ./
    ../dslice push junwha/dslice-base-py:$PY_VERSION
done

TORCH_VERSION_PAIRS=(
    "2.4.1 0.19.1"
)
for PY_VERSION in 3.8 3.10 3.12; do
    for TORCH_VERSION_PAIR in "${TORCH_VERSION_PAIRS[@]}"; do
        read -r TORCH_VERSION TORCH_VISION_VERSION <<< "$TORCH_VERSION_PAIR"
        docker build -t junwha/dslice-base-torch:py$PY_VERSION-torch$TORCH_VERSION \
            --build-arg TORCH_VERSION=$TORCH_VERSION \
            --build-arg TORCH_VISION_VERSION=$TORCH_VISION_VERSION \
            --build-arg PY_VERSION=$PY_VERSION \
            -f Dockerfile.torch ./
        ../dslice push junwha/dslice-base-torch:py$PY_VERSION-torch$TORCH_VERSION
    done
done

