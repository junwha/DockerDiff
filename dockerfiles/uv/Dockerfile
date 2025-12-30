ARG PY_VERSION
ARG DOCKER_CUDA_VERSION=12.4.1
FROM nvidia/cuda:${DOCKER_CUDA_VERSION}-cudnn-devel-ubuntu22.04

ARG PY_VERSION

# For A100, RTX4090, H100, and H200
ENV TORCH_CUDA_ARCH_LIST='7.0 7.5 8.0 8.6 8.9 9.0+PTX'
ENV MAX_JOBS=2
ENV NVCC_THREADS=8

ENV DEBIAN_FRONTEND=noninteractive
ENV CUDA_HOME=/usr/local/cuda
ENV SETUPTOOLS_USE_DISTUTILS=stdlib

RUN apt-get update -y

# Utils
RUN apt-get install -y vim git bzip2 tmux wget tar htop unzip

# SSH
RUN apt-get install -y ssh openssh-server
RUN mkdir -p /var/run/sshd
RUN echo "root:root" | chpasswd
RUN echo "Port 22" >> /etc/ssh/sshd_config
RUN echo "PermitRootLogin yes" >> /etc/ssh/sshd_config
EXPOSE 22

RUN apt-get update -y && apt-get install -y software-properties-common
RUN apt-key adv --fetch-keys https://developer.download.nvidia.com/compute/cuda/repos/ubuntu1804/x86_64/7fa2af80.pub 
RUN add-apt-repository -y "deb https://developer.download.nvidia.com/devtools/repos/ubuntu22.04/$(dpkg --print-architecture) /"
RUN apt-get install -y nsight-systems-2024.6.2
RUN apt-get install -y mesa-utils x11-apps
RUN apt-get install -y freeglut3-dev libglu1-mesa-dev mesa-common-dev libxkbfile-dev libgl1-mesa-glx

ENV LIBGL_DRIVERS_PATH=/usr/lib/x86_64-linux-gnu/dri
ENV LIBGL_ALWAYS_INDIRECT=1

# Build tools
RUN rm /etc/apt/sources.list.d/archive_uri-https_developer_download_nvidia_com_devtools_repos_ubuntu22_04_amd64-jammy.list
RUN apt-get update -y && apt-get install -y gcc-12 g++-12 ninja-build cmake build-essential autoconf libtool automake git
RUN apt-get install -y ffmpeg libsm6 libxext6 libgl1

# Utils
RUN apt-get install -y vim git bzip2 tmux wget tar htop curl

RUN add-apt-repository ppa:deadsnakes/ppa && apt-get install -y python${PY_VERSION} python${PY_VERSION}-dev python${PY_VERSION}-venv
RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python${PY_VERSION} 1
RUN update-alternatives --set python3 /usr/bin/python${PY_VERSION}
RUN ln -sf /usr/bin/python${PY_VERSION}-config /usr/bin/python3-config 
RUN curl -sS https://bootstrap.pypa.io/get-pip.py | python${PY_VERSION}

RUN apt-get install -y python3-setuptools python3-dev libpython${PY_VERSION}-dev

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
