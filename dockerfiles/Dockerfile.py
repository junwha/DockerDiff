ARG PY_VERSION
ARG BASE_TAG
FROM junwha/dslice-base:${BASE_TAG}

ARG PY_VERSION

RUN conda init && \
    conda install python=$PY_VERSION -y && \
    conda install -c "nvidia/label/cuda-$(cat /CUDA_VERSION)" cuda -y
