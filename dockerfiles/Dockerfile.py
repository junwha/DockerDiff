ARG PY_VERSION
FROM junwha/dslice-base

ARG PY_VERSION

RUN conda init && \
    conda install python=$PY_VERSION -y && \
    conda install -c "nvidia/label/cuda-$(cat /CUDA_VERSION)" cuda -y
