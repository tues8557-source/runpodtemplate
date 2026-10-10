#!/usr/bin/env bash
# custom_nodes.txt에 적힌 노드를 설치 (이미지 빌드 중에 실행됨)
# 패키지 설치가 실패하면 빌드도 실패 → 충돌을 Pod가 아닌 빌드 단계에서 발견
set -euo pipefail
LIST="$1"
DEST=/opt/ComfyUI/custom_nodes
cd "$DEST"

tr -d '\r' < "$LIST" | while read -r url ref _; do
    [ -z "${url:-}" ] && continue
    [[ "$url" == \#* ]] && continue
    name="$(basename "$url" .git)"
    echo "=== 커스텀 노드 설치: $name ${ref:-(최신)} ==="
    if [ -n "${ref:-}" ]; then
        git clone --filter=blob:none "$url" "$name"
        git -C "$name" checkout "$ref"
    else
        git clone --depth 1 "$url" "$name"
    fi
    if [ -f "$name/requirements.txt" ]; then
        uv pip install -c /opt/constraints.txt -r "$name/requirements.txt"
    fi
    if [ -f "$name/install.py" ]; then
        ( cd "$name" && python install.py )
    fi
done

# 설치 후에도 PyTorch 버전이 그대로인지 확인
uv pip freeze | grep -E '^(torch|torchvision|torchaudio)==' | diff - /opt/constraints.txt \
    && echo "=== PyTorch 버전 유지 확인 ==="
