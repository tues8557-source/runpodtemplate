# ComfyUI RunPod 커스텀 이미지

## 포함된 것
- CUDA 13.0 + PyTorch(cu130), comfy-kitchen[cublas] (Blackwell에서 NVFP4 가속)
- SageAttention 2 (A100 / RTX 4090 / RTX 5090·PRO 4500 대상으로 빌드)
- ComfyUI 최신 + ComfyUI-Manager(공식 pip 버전, `--enable-manager`)
- 커스텀 노드: ComfyUI-RunpodDirect, Civicomfy
- JupyterLab(bash 터미널, 경로 표시), Hugging Face CLI(`hf`)
- 도구: ffmpeg, aria2, git-lfs, tmux, htop, nvtop

## 1. GitHub 준비
1. 새 저장소를 만들고 이 폴더의 파일을 그대로 올립니다 (`.github` 폴더 포함).
2. Docker Hub → Account settings → Personal access tokens에서 Read & Write 토큰 생성
3. GitHub 저장소 → Settings → Secrets and variables → Actions에 등록
   - `DOCKERHUB_USERNAME`: Docker Hub 아이디
   - `DOCKERHUB_TOKEN`: 위에서 만든 토큰
4. main 브랜치에 올리면 Actions 탭에서 빌드가 시작됩니다 (첫 빌드 30~90분 예상).

## 2. RunPod 템플릿
- Container Image: `아이디/comfyui-runpod:latest` (안정적으로 쓰려면 숫자 태그 사용)
- Container Disk: 30GB 이상
- Volume Mount Path: `/workspace`
- HTTP 포트: `8188, 8888` / TCP 포트: `22`
- 환경변수 (RunPod Secrets에 저장 후 `{{ RUNPOD_SECRET_이름 }}` 형태로 연결 권장)
  - `JUPYTER_PASSWORD`: Jupyter 접속 비밀번호 (꼭 설정)
  - `HF_TOKEN`: Hugging Face 토큰
  - `CIVITAI_API_KEY`: Civitai API 키 (Civicomfy가 자동 인식)
  - `COMFY_DATA_DIR`: 모델이 들어있는 폴더의 상위 경로 (기본 `/workspace/runpod-slim/ComfyUI`)
  - `COMFYUI_ARGS`: ComfyUI 추가 실행 옵션 (선택)
- Pod 배포 시 CUDA 버전 필터를 13.0 이상으로 설정

## 3. 폴더 구조
- 코드와 파이썬 환경: `/opt/ComfyUI`, `/opt/venv` (컨테이너 디스크, 빠름)
- `models`, `input`, `output`, `user` → `COMFY_DATA_DIR` 아래로 연결 (네트워크 볼륨, 유지됨)

## 4. 첫 실행 확인
- 로그에 comfy-kitchen 백엔드가 `cuda`로 표시되는지 (Blackwell GPU)
- 로그에 SageAttention 사용 문구가 나오는지
- 터미널: `python -c "import torch, sageattention; print(torch.__version__)"`

## 참고
- 매니저로 설치한 커스텀 노드는 Pod를 끄면 사라집니다. 계속 쓸 노드는 Dockerfile의
  커스텀 노드 부분에 `git clone` 줄을 추가하고 다시 빌드하세요.
- 특정 모델에서 결과가 검게 나오는 등 이상하면 `--use-sage-attention`이 원인일 수 있습니다.
  start.sh에서 해당 옵션을 빼고 테스트해 보세요.
