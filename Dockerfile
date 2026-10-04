# syntax=docker/dockerfile:1
# ComfyUI for RunPod — CUDA 13.0 / PyTorch cu130 / comfy-kitchen[cublas] / SageAttention
# 대상 GPU: A100(8.0), RTX 4090(8.9), RTX 5090·RTX PRO 4500(12.0)

ARG CUDA_VERSION=13.0.0
ARG UBUNTU=ubuntu24.04

############################################################
# 1단계: 빌드 (컴파일 도구가 있는 devel 이미지)
############################################################
FROM nvidia/cuda:${CUDA_VERSION}-devel-${UBUNTU} AS builder

# 비워두면 빌드 시점의 최신 안정판 PyTorch(cu130)를 설치. 고정하려면 예: 2.13.0
ARG TORCH_VERSION=
ARG TORCH_CUDA_ARCH_LIST="8.0;8.9;12.0"
# GitHub 무료 빌드 서버(메모리 16GB) 기준으로 낮게 설정
ARG MAX_JOBS=2
ARG COMFYUI_REF=master

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_NO_CACHE_DIR=1 \
    UV_NO_CACHE=1 \
    VIRTUAL_ENV=/opt/venv \
    PATH=/opt/venv/bin:$PATH

RUN apt-get update && apt-get install -y --no-install-recommends \
        python3.12 python3.12-venv python3.12-dev \
        git build-essential ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

RUN python3.12 -m venv /opt/venv \
    && pip install --upgrade pip uv wheel setuptools packaging ninja

# PyTorch (CUDA 13.0 빌드)
RUN if [ -n "$TORCH_VERSION" ]; then T="torch==${TORCH_VERSION}"; else T="torch"; fi \
    && uv pip install "$T" torchvision torchaudio --index-url https://download.pytorch.org/whl/cu130 \
    && uv pip freeze | grep -E '^(torch|torchvision|torchaudio)==' > /opt/constraints.txt \
    && cat /opt/constraints.txt
# ↑ constraints.txt: 이후 설치되는 패키지가 torch 버전을 바꾸지 못하게 고정

# ComfyUI 최신 + 매니저(pip 버전) + comfy-kitchen cuBLAS 버전
RUN git clone --depth 1 --branch ${COMFYUI_REF} https://github.com/Comfy-Org/ComfyUI.git /opt/ComfyUI \
    && cd /opt/ComfyUI \
    && uv pip install -c /opt/constraints.txt -r requirements.txt -r manager_requirements.txt \
    && uv pip install -c /opt/constraints.txt "comfy-kitchen[cublas]"

# 커스텀 노드 (여기에 줄을 추가하면 이미지에 영구 포함)
RUN cd /opt/ComfyUI/custom_nodes \
    && git clone --depth 1 https://github.com/MadiatorLabs/ComfyUI-RunpodDirect.git \
    && git clone --depth 1 https://github.com/MoonGoblinDev/Civicomfy.git \
    && for d in */; do \
         if [ -f "$d/requirements.txt" ]; then uv pip install -c /opt/constraints.txt -r "$d/requirements.txt"; fi; \
       done

# Jupyter(터미널용), Hugging Face CLI
RUN uv pip install -c /opt/constraints.txt jupyterlab "huggingface_hub[hf_xet]"

# SageAttention 2 — GPU 없는 빌드 서버에서도 되도록 대상 아키텍처를 직접 지정
ENV TORCH_CUDA_ARCH_LIST=${TORCH_CUDA_ARCH_LIST} \
    MAX_JOBS=${MAX_JOBS} \
    EXT_PARALLEL=1 \
    NVCC_APPEND_FLAGS="--threads 2"
COPY files/patch_sage.py /tmp/patch_sage.py
# 2.x 빌드에 실패해도 이미지 빌드는 멈추지 않고 1.x(Triton 기반)로 대체
RUN git clone --depth 1 https://github.com/thu-ml/SageAttention.git /tmp/sage \
    && cd /tmp/sage \
    && python /tmp/patch_sage.py \
    && ( pip install . --no-build-isolation \
         || ( echo "!!!!! SAGE2_BUILD_FAILED: SageAttention 2 빌드 실패, 1.x로 대체합니다 !!!!!" \
              && uv pip install -c /opt/constraints.txt sageattention==1.0.6 ) ) \
    && python -c "import importlib.metadata as m; print('SageAttention 설치 버전:', m.version('sageattention'))" \
    && rm -rf /tmp/sage /tmp/patch_sage.py

############################################################
# 2단계: 실행용 (가벼운 runtime 이미지)
############################################################
FROM nvidia/cuda:${CUDA_VERSION}-runtime-${UBUNTU}

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    VIRTUAL_ENV=/opt/venv \
    PATH=/opt/venv/bin:$PATH \
    SHELL=/bin/bash \
    HF_HOME=/workspace/.cache/huggingface

# build-essential, python3.12-dev: Triton이 실행 중에 작은 코드를 컴파일할 때 필요
RUN apt-get update && apt-get install -y --no-install-recommends \
        python3.12 python3.12-venv python3.12-dev build-essential \
        git git-lfs ca-certificates curl wget nano unzip \
        ffmpeg aria2 tmux htop nvtop openssh-server \
        libgl1 libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/* \
    && git lfs install \
    && git config --global --add safe.directory '*'

COPY --from=builder /opt/venv /opt/venv
COPY --from=builder /opt/ComfyUI /opt/ComfyUI
COPY --from=builder /opt/constraints.txt /opt/constraints.txt

COPY files/start.sh /start.sh
COPY files/jupyter_server_config.py /root/.jupyter/jupyter_server_config.py
COPY files/bashrc_extra /tmp/bashrc_extra
RUN chmod +x /start.sh && cat /tmp/bashrc_extra >> /root/.bashrc && rm /tmp/bashrc_extra

WORKDIR /opt/ComfyUI
EXPOSE 8188 8888 22
CMD ["/start.sh"]
