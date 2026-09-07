import subprocess, time, urllib.request, os

HOST = "192.168.200.128"
KEY = os.path.expanduser("~/.ssh/id_ed25519_02adapter")
SSH = ["ssh", "-i", KEY, "-o", "StrictHostKeyChecking=no", f"root@{HOST}"]
C = "deploy-confidential-adapter-1"

def ssh(cmd):
    r = subprocess.run(SSH + [cmd], capture_output=True, text=True)
    return r

def models_code():
    try:
        req = urllib.request.Request(f"http://{HOST}:18080/v1/models")
        with urllib.request.urlopen(req, timeout=5) as r:
            return r.status
    except Exception:
        return 0

print("stopping...")
r = ssh(f"docker stop {C}")
print("stop_rc=", r.returncode, r.stderr.strip()[:100])
time.sleep(1)

print("starting...")
r = ssh(f"docker start {C}")
print("start_rc=", r.returncode, r.stderr.strip()[:100])

t0 = time.perf_counter()
code = 0
while time.perf_counter() - t0 < 120:
    code = models_code()
    if code == 200:
        break
    time.sleep(0.1)

dt = time.perf_counter() - t0
print(f"ready_after_start={dt:.3f}s final_code={code}")
