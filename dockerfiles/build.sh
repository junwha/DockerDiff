#!/bin/bash
CUDA_VERSION=12.4.1 # or 11.8.0
CUDA_PREFIX=cuda$CUDA_VERSION
docker build -t junwha/dslice-base:$CUDA_PREFIX --build-arg DOCKER_CUDA_VERSION=$CUDA_VERSION -f Dockerfile.base ./
# ../dslice push junwha/dslice-base:$CUDA_PREFIX
docker push junwha/ds1ice-base:$CUDA_PREFIX

for PY_VERSION in 3.9 3.11; do # 3.8 3.10 3.12; do
    docker build -t junwha/dslice-base-py:$CUDA_PREFIX-py$PY_VERSION --build-arg PY_VERSION=$PY_VERSION --build-arg BASE_TAG=$CUDA_PREFIX -f Dockerfile.py ./
    # ../dslice push junwha/dslice-base-py:$CUDA_PREFIX-py$PY_VERSION
    docker push junwha/dslice-base-py:$CUDA_PREFIX-py$PY_VERSION

done

TORCH_VERSION_PAIRS=(
    "2.5.0 0.20.0"
)

for PY_VERSION in 3.9 3.11; do # 3.8 3.10 3.12; do
    for TORCH_VERSION_PAIR in "${TORCH_VERSION_PAIRS[@]}"; do
        read -r TORCH_VERSION TORCH_VISION_VERSION <<< "$TORCH_VERSION_PAIR"
        docker build -t junwha/dslice-base-torch:$CUDA_PREFIX-py$PY_VERSION-torch$TORCH_VERSION \
            --build-arg BASE_TAG=$CUDA_PREFIX-py$PY_VERSION \
            --build-arg TORCH_VERSION=$TORCH_VERSION \
            --build-arg TORCH_VISION_VERSION=$TORCH_VISION_VERSION \
            -f Dockerfile.torch ./
        ../dslice push junwha/dslice-base-torch:$CUDA_PREFIX-py$PY_VERSION-torch$TORCH_VERSION
        docker push junwha/dslice-base-torch:$CUDA_PREFIX-py$PY_VERSION-torch$TORCH_VERSION
    done
done

