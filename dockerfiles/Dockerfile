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