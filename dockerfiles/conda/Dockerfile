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

# RUN conda init && \
#     pip install torch==$TORCH_VERSION torchvision==$TORCH_VISION_VERSION torchaudio==$TORCH_VERSION --index-url https://download.pytorch.org/whl/cu$(cat /CUDA_VERSION | awk -F. '{print $1$2}')
