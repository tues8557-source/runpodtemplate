#!/usr/bin/env bash
# Pod 시작 시 실행: 볼륨 연결 → SSH → Jupyter → ComfyUI
set -u

COMFY=/opt/ComfyUI
DATA="${COMFY_DATA_DIR:-/workspace/runpod-slim/ComfyUI}"

echo "=== 데이터 폴더: $DATA ==="

# 1) 모델·입력·출력·사용자설정을 네트워크 볼륨으로 연결
#    → RunpodDirect, Civicomfy, 매니저가 받는 모델도 자동으로 볼륨에 저장됨
mkdir -p "$DATA"
for d in models input output user; do
    mkdir -p "$DATA/$d"
    if [ -d "$COMFY/$d" ] && [ ! -L "$COMFY/$d" ]; then
        # 이미지 기본 폴더 구조(빈 하위 폴더)만 볼륨에 복사, 기존 파일은 덮어쓰지 않음
        cp -r --update=none "$COMFY/$d/." "$DATA/$d/" 2>/dev/null || true
        rm -rf "$COMFY/$d"
    fi
    ln -sfn "$DATA/$d" "$COMFY/$d"
done

# 2) 환경변수(HF_TOKEN 등)를 SSH 접속 세션에서도 쓸 수 있게 저장
export -p | grep -E 'declare -x (HF_|CIVITAI_|COMFY|RUNPOD_)' > /etc/rp_env.sh || true

# 3) SSH (RunPod 계정에 공개키를 등록해두면 PUBLIC_KEY로 전달됨)
if [ -n "${PUBLIC_KEY:-}" ]; then
    mkdir -p /root/.ssh /run/sshd
    echo "$PUBLIC_KEY" >> /root/.ssh/authorized_keys
    chmod 700 /root/.ssh && chmod 600 /root/.ssh/authorized_keys
    rm -f /etc/ssh/ssh_host_* && ssh-keygen -A >/dev/null
    /usr/sbin/sshd && echo "=== SSH 시작 ==="
fi

# 4) JupyterLab (포트 8888)
if [ "${JUPYTER_ENABLE:-1}" = "1" ]; then
    if [ -n "${JUPYTER_PASSWORD:-}" ]; then
        jupyter lab --IdentityProvider.token="$JUPYTER_PASSWORD" &
    else
        echo "!!! JUPYTER_PASSWORD가 없어 임시 토큰을 생성합니다. 아래 로그의 token= 값을 사용하세요."
        jupyter lab &
    fi
fi

# 5) ComfyUI (포트 8188) — 꺼지면 5초 뒤 자동 재시작
if [ "${COMFYUI_AUTOSTART:-1}" = "1" ]; then
    (
        cd "$COMFY"
        while true; do
            python main.py --listen 0.0.0.0 --port 8188 \
                --enable-manager --use-sage-attention \
                ${COMFYUI_ARGS:-}
            echo "=== ComfyUI 종료됨, 5초 후 재시작 ==="
            sleep 5
        done
    ) 2>&1 | tee -a /var/log/comfyui.log &
fi

sleep infinity
