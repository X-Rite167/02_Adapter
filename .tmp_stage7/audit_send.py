import json, time, urllib.request, urllib.error

URL = "http://192.168.200.128:18080/v1/chat/completions"
MODEL = "cmaas-deepseek-v4-flash-0731"
N = 10

ok = 0
for i in range(N):
    body = json.dumps({
        "model": MODEL,
        "messages": [{"role": "user", "content": f"audit completeness test {i}"}],
        "max_tokens": 8,
        "stream": False,
    }).encode()
    try:
        req = urllib.request.Request(URL, data=body, headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=120) as r:
            code = r.status
    except urllib.error.HTTPError as e:
        code = e.code
    ok += 1 if code == 200 else 0
    time.sleep(0.2)

print(f"sent={N} ok={ok}")
