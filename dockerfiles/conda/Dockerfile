ARG PY_VERSION
ARG DOCKER_CUDA_VERSION=12.4.1
FROM junwha/ddiff-base-common:cu${DOCKER_CUDA_VERSION}-py${PY_VERSION}
ARG PY_VERSION
ARG DOCKER_CUDA_VERSION

# Conda
RUN wget https://repo.anaconda.com/archive/Anaconda3-2024.10-1-Linux-x86_64.sh && \
    chmod +x ./Anaconda3-2024.10-1-Linux-x86_64.sh && \
    ./Anaconda3-2024.10-1-Linux-x86_64.sh -b && \
    rm ./Anaconda3-2024.10-1-Linux-x86_64.sh
ENV PATH /root/anaconda3/bin:$PATH

RUN conda init && \
    conda install python=$PY_VERSION -y && \
    conda install -c "nvidia/label/cuda-$DOCKER_CUDA_VERSION" cuda -y

# torch installer
COPY <<EOF /usr/local/bin/install_torch_env
#!/bin/bash
set -e
TORCH_VER=\$1
VISION_VER=\$2
CUDA_VER=\$3
FLASH_ATTN_LINK=\$4

conda create -n torch\${TORCH_VER}

export PATH_BCK=\$PATH
export PATH=/root/anaconda/envs/torch\${TORCH_VER}:\$PATH

pip install --no-cache-dir torch=="\${TORCH_VER}" torchvision=="\${VISION_VER}" torchaudio=="\${TORCH_VER}" --index-url "https://download.pytorch.org/whl/\${CUDA_VER}"
pip install --no-cache-dir \$FLASH_ATTN_LINK

"""conda activate torch\${TORCH_VER} && echo "export PATH=/root/anaconda/envs/torch\${TORCH_VER}:\\\$PATH && source activate torch\${TORCH_VER}" &>> ~/.bashrc""" > /usr/local/bin/init_torch\${TORCH_VER}
chmod +x /usr/local/bin/init_torch\${TORCH_VER}

export PATH=\$PATH_BCK

EOF

RUN chmod +x /usr/local/bin/install_torch_env

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
