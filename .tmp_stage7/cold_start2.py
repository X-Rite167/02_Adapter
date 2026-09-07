import subprocess, time, urllib.request, socket, os

HOST = "192.168.200.128"
KEY = os.path.expanduser("~/.ssh/id_ed25519_02adapter")
SSH = ["ssh", "-i", KEY, "-o", "StrictHostKeyChecking=no", f"root@{HOST}"]
C = "deploy-confidential-adapter-1"

def ssh(cmd):
    return subprocess.run(SSH + [cmd], capture_output=True, text=True)

def port_open():
    s = socket.socket()
    s.settimeout(1)
    try:
        s.connect((HOST, 18080))
        return True
    except Exception:
        return False
    finally:
        s.close()

def models_code():
    try:
        req = urllib.request.Request(f"http://{HOST}:18080/v1/models")
        with urllib.request.urlopen(req, timeout=3) as r:
            return r.status
    except Exception:
        return 0

print("STEP1 stop container")
ssh(f"docker stop {C}")
# wait until port closed
for i in range(100):
    if not port_open():
        break
    time.sleep(0.1)
print(f"port_closed_after_stop={not port_open()}")

print("STEP2 confirm port closed, then start + time to ready")
t_start_wall = time.perf_counter()
ssh(f"docker start {C}")
t_after_start_cmd = time.perf_counter()

code = 0
t_ready = None
while time.perf_counter() - t_start_wall < 120:
    code = models_code()
    if code == 200:
        t_ready = time.perf_counter()
        break
    time.sleep(0.05)

print(f"start_cmd_duration={t_after_start_cmd - t_start_wall:.3f}s")
print(f"ready_since_start_call={t_ready - t_start_wall:.3f}s")
print(f"ready_since_start_cmd_return={t_ready - t_after_start_cmd:.3f}s")
print(f"final_code={code}")
