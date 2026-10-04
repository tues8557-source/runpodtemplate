"""SageAttention setup.py가 GPU 없는 빌드 서버에서도 TORCH_CUDA_ARCH_LIST를 쓰도록 보정."""
import os

path = "setup.py"
src = open(path, encoding="utf-8").read()
target = "compute_capabilities = set()"

if target not in src:
    print("[patch_sage] 대상 줄을 찾지 못해 원본 그대로 진행합니다.")
else:
    patch = '''
_env_arch = os.environ.get("TORCH_CUDA_ARCH_LIST", "")
for _a in _env_arch.replace(" ", ";").split(";"):
    _a = _a.strip().replace("+PTX", "")
    if _a:
        compute_capabilities.add(_a)
print("[patch_sage] 대상 아키텍처:", compute_capabilities)
'''
    if "import os" not in src:
        src = "import os\n" + src
    src = src.replace(target, target + patch, 1)
    open(path, "w", encoding="utf-8").write(src)
    print("[patch_sage] setup.py 보정 완료")
