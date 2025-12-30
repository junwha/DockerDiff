ARG PY_VERSION
ARG DOCKER_CUDA_VERSION=12.4.1
FROM junwha/ddiff-base-common:cu${DOCKER_CUDA_VERSION}-py${PY_VERSION}
ARG PY_VERSION

RUN curl -LsSf https://astral.sh/uv/0.8.14/install.sh | sh

SHELL ["/bin/bash", "-c"]
ENV PATH=/root/.local/bin:$PATH

RUN uv python pin ${PY_VERSION}
RUN uv pip install --no-cache --system ipython tqdm rich jupyter jupyterlab ipykernel pandas einops safetensors pyyaml requests psutil opencv-python-headless matplotlib seaborn scikit-learn scipy pillow tensorboard h5py triton

# torch installer
COPY <<EOF /usr/local/bin/install_torch_env
#!/bin/bash
set -e
TORCH_VER=\$1
VISION_VER=\$2
CUDA_VER=\$3
FLASH_ATTN_LINK=\$4

BASE_DIR=/ddiff-base/py\${PY_VERSION}-torch\${TORCH_VER}
mkdir -p "\$BASE_DIR" && cd "\$BASE_DIR"
uv venv --python "\${PY_VERSION}" --system-site-packages --seed
uv pip install --no-cache torch=="\${TORCH_VER}" torchvision=="\${VISION_VER}" torchaudio=="\${TORCH_VER}" --index-url "https://download.pytorch.org/whl/\${CUDA_VER}"
uv pip install --no-cache \$FLASH_ATTN_LINK
echo "ln -sfn \${BASE_DIR}/.venv ./.venv && [ -f pyproject.toml ] && uv add torch==\${TORCH_VER} torchvision==\${VISION_VER} torchaudio==\${TORCH_VER}; echo Created uv virtual environment with torch==\${TORCH_VER}" > /usr/local/bin/uv_init_torch\${TORCH_VER}
chmod +x /usr/local/bin/uv_init_torch\${TORCH_VER}
EOF
RUN chmod +x /usr/local/bin/install_torch_env

ENV UV_NO_CACHE=1

# pytorch 2.4.1 (251209 Update)
RUN install_torch_env 2.4.1 0.19.1 cu124 https://github.com/mjun0812/flash-attention-prebuild-wheels/releases/download/v0.3.12/flash_attn-2.8.0+cu124torch2.4-cp310-cp310-linux_x86_64.whl

# pytorch 2.5.1 (251209 Update)
RUN install_torch_env 2.5.1 0.20.1 cu124 https://github.com/mjun0812/flash-attention-prebuild-wheels/releases/download/v0.4.11/flash_attn-2.8.3+cu124torch2.5-cp310-cp310-linux_x86_64.whl

# pytorch 2.6.0 (251209 Update)
RUN install_torch_env 2.6.0 0.21.0 cu124 https://github.com/mjun0812/flash-attention-prebuild-wheels/releases/download/v0.4.11/flash_attn-2.8.3+cu124torch2.6-cp310-cp310-linux_x86_64.whl

# pytorch 2.7.1 (251209 Update)
RUN install_torch_env 2.7.1 0.22.1 cu126 https://github.com/mjun0812/flash-attention-prebuild-wheels/releases/download/v0.4.11/flash_attn-2.8.3+cu126torch2.7-cp310-cp310-linux_x86_64.whl

# pytorch 2.9.0 (251209 Update)
RUN install_torch_env 2.9.0 0.24.0 cu126 https://github.com/mjun0812/flash-attention-prebuild-wheels/releases/download/v0.4.17/flash_attn-2.6.3+cu126torch2.9-cp310-cp310-linux_x86_64.whl
