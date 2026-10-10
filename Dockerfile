# syntax=docker/dockerfile:1
# ComfyUI for RunPod — CUDA 13.0 / PyTorch cu130 / comfy-kitchen[cublas] / SageAttention
# 대상 GPU: A100(8.0), RTX 4090(8.9), RTX 5090·RTX PRO 4500(12.0)
#
# 레이어는 "잘 안 바뀌는 것 → 자주 바뀌는 것" 순서로 나눠져 있습니다.
# 빌드 캐시 덕분에 시스템 패키지·PyTorch·SageAttention 레이어는 다시 빌드해도 그대로 재사용되고,
# RunPod 서버가 예전 버전을 받아둔 적이 있다면 바뀐 레이어만 새로 받습니다.

ARG CUDA_VERSION=13.0.0
ARG UBUNTU=ubuntu24.04
# PyTorch 버전 고정 (SageAttention 휠과 반드시 같아야 함). 올릴 때는 이 값만 바꾸면 됨
ARG TORCH_VERSION=2.14.1

############################################################
# 1단계: SageAttention 휠만 만드는 빌드 전용 단계 (최종 이미지에는 휠 파일만 들어감)
############################################################
FROM nvidia/cuda:${CUDA_VERSION}-devel-${UBUNTU} AS sage-builder

ARG TORCH_VERSION
ARG TORCH_CUDA_ARCH_LIST="8.0;8.9;12.0"
ARG MAX_JOBS=2

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_NO_CACHE_DIR=1 \
    UV_NO_CACHE=1 \
    VIRTUAL_ENV=/opt/venv \
    PATH=/opt/venv/bin:$PATH

RUN apt-get update && apt-get install -y --no-install-recommends \
        python3.12 python3.12-venv python3.12-dev git build-essential ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN python3.12 -m venv /opt/venv \
    && pip install --upgrade pip uv wheel setuptools packaging ninja \
    && uv pip install "torch==${TORCH_VERSION}" --index-url https://download.pytorch.org/whl/cu130

ENV TORCH_CUDA_ARCH_LIST=${TORCH_CUDA_ARCH_LIST} \
    MAX_JOBS=${MAX_JOBS} \
    EXT_PARALLEL=1 \
    NVCC_APPEND_FLAGS="--threads 2"

COPY files/patch_sage.py /tmp/patch_sage.py
# 빌드에 실패해도 멈추지 않음 → 최종 단계에서 1.x(Triton 기반)로 대체
RUN mkdir -p /wheels \
    && git clone --depth 1 https://github.com/thu-ml/SageAttention.git /tmp/sage \
    && cd /tmp/sage \
    && python /tmp/patch_sage.py \
    && ( pip wheel . --no-build-isolation --no-deps -w /wheels \
         || echo "!!!!! SAGE2_BUILD_FAILED: SageAttention 2 빌드 실패, 1.x로 대체합니다 !!!!!" ) \
    && ls -la /wheels

############################################################
# 2단계: 실제로 배포되는 이미지
############################################################
FROM nvidia/cuda:${CUDA_VERSION}-runtime-${UBUNTU}

ARG TORCH_VERSION

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    UV_NO_CACHE=1 \
    VIRTUAL_ENV=/opt/venv \
    PATH=/opt/venv/bin:$PATH \
    SHELL=/bin/bash \
    HF_HOME=/workspace/.cache/huggingface

# [레이어 1] 시스템 패키지 — 거의 안 바뀜
# build-essential, python3.12-dev: Triton이 실행 중에 작은 코드를 컴파일할 때 필요
RUN apt-get update && apt-get install -y --no-install-recommends \
        python3.12 python3.12-venv python3.12-dev build-essential \
        git git-lfs ca-certificates curl wget nano unzip \
        ffmpeg aria2 tmux htop nvtop openssh-server \
        libgl1 libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/* \
    && git lfs install \
    && git config --global --add safe.directory '*'

# [레이어 2] PyTorch — 가장 큰 레이어, TORCH_VERSION을 바꿀 때만 다시 만들어짐
RUN python3.12 -m venv /opt/venv \
    && pip install --upgrade pip uv \
    && uv pip install "torch==${TORCH_VERSION}" torchvision torchaudio \
         --index-url https://download.pytorch.org/whl/cu130 \
    && uv pip freeze | grep -E '^(torch|torchvision|torchaudio)==' > /opt/constraints.txt \
    && cat /opt/constraints.txt

# [레이어 3] SageAttention
COPY --from=sage-builder /wheels /tmp/wheels
RUN if ls /tmp/wheels/*.whl >/dev/null 2>&1; then \
        uv pip install -c /opt/constraints.txt /tmp/wheels/*.whl; \
    else \
        uv pip install -c /opt/constraints.txt sageattention==1.0.6; \
    fi \
    && python -c "import importlib.metadata as m; print('SageAttention 설치 버전:', m.version('sageattention'))" \
    && rm -rf /tmp/wheels

# [레이어 4] Jupyter, Hugging Face CLI — 거의 안 바뀜
RUN uv pip install -c /opt/constraints.txt jupyterlab "huggingface_hub[hf_xet]"

# ---------- 여기부터는 빌드할 때마다 새로 만들어짐 (ComfyUI를 최신으로) ----------
ARG CACHE_BUST=0
ARG COMFYUI_REF=master

# [레이어 5] ComfyUI 최신 + 매니저(pip 버전) + comfy-kitchen cuBLAS 버전
RUN echo "build ${CACHE_BUST}" \
    && git clone --depth 1 --branch ${COMFYUI_REF} https://github.com/Comfy-Org/ComfyUI.git /opt/ComfyUI \
    && cd /opt/ComfyUI \
    && uv pip install -c /opt/constraints.txt -r requirements.txt -r manager_requirements.txt \
    && uv pip install -c /opt/constraints.txt "comfy-kitchen[cublas]"

# [레이어 6] 커스텀 노드 — files/custom_nodes.txt 목록대로 설치
COPY files/custom_nodes.txt files/install_nodes.sh /tmp/nodes/
RUN bash /tmp/nodes/install_nodes.sh /tmp/nodes/custom_nodes.txt && rm -rf /tmp/nodes

# [레이어 7] 시작 스크립트와 설정 — 몇 KB
COPY files/start.sh /start.sh
COPY files/jupyter_server_config.py /root/.jupyter/jupyter_server_config.py
COPY files/bashrc_extra /tmp/bashrc_extra
RUN chmod +x /start.sh && cat /tmp/bashrc_extra >> /root/.bashrc && rm /tmp/bashrc_extra

WORKDIR /opt/ComfyUI
EXPOSE 8188 8888 22
CMD ["/start.sh"]
