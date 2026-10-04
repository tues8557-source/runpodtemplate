c = get_config()  # noqa

c.ServerApp.ip = "0.0.0.0"
c.ServerApp.port = 8888
c.ServerApp.open_browser = False
c.ServerApp.allow_root = True
c.ServerApp.allow_origin = "*"      # RunPod 프록시 주소로 접속 허용
c.ServerApp.trust_xheaders = True

# 파일 탐색기와 새 터미널의 시작 위치
c.ServerApp.root_dir = "/workspace"

# 터미널을 sh가 아닌 bash로 실행 → '>'나 '$'만 나오는 문제 해결, 경로 표시
c.ServerApp.terminado_settings = {"shell_command": ["/bin/bash"]}
