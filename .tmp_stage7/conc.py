import json, time, threading, urllib.request, urllib.error, concurrent.futures, sys

URL = "http://192.168.200.128:18080/v1/chat/completions"
MODEL = "cmaas-deepseek-v4-flash-0731"

def one_req(i):
    body = json.dumps({
        "model": MODEL,
        "messages": [{"role": "user", "content": "Reply one word: ok"}],
        "max_tokens": 8,
        "stream": False,
    }).encode()
    t0 = time.perf_counter()
    try:
        req = urllib.request.Request(URL, data=body, headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=120) as r:
            code = r.status
            resp = r.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        code = e.code
        resp = e.read().decode("utf-8", "replace")
    except Exception as e:
        code = "ERR"
        resp = str(e)
    dt = time.perf_counter() - t0
    return code, dt, resp

def sweep(C):
    t0 = time.perf_counter()
    with concurrent.futures.ThreadPoolExecutor(max_workers=C) as ex:
        results = list(ex.map(one_req, range(C)))
    wall = time.perf_counter() - t0
    codes = [r[0] for r in results]
    lat = [r[1] for r in results]
    ok = codes.count(200)
    r429 = codes.count(429)
    others = [c for c in codes if c not in (200, 429)]
    line = f"C={C} codes={codes} ok={ok} 429={r429} other={others} wall={wall:.3f}s lat_avg={sum(lat)/len(lat):.3f}s lat_max={max(lat):.3f}s"
    print(line)
    for c, dt, resp in results:
        if c == 429:
            print(f"  429_body: {resp[:200]}")
            break

for C in [1, 2, 4, 5, 8, 10]:
    sweep(C)
