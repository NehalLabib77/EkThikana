"""Retry with longer timeout."""
import urllib.request, json, ssl, time

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

def get(path, timeout=30):
    url = f"https://ekthikana-api-x473.onrender.com{path}"
    req = urllib.request.Request(url, method="GET")
    req.add_header("Accept", "application/json")
    try:
        r = urllib.request.urlopen(req, context=ctx, timeout=timeout)
        return r.status, r.read().decode("utf-8")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", errors="replace")
    except Exception as e:
        return -1, str(e)

for attempt in range(3):
    print(f"\n--- attempt {attempt+1} ---")
    code, body = get("/api/health")
    print("health:", code)
    if code == 200:
        break
    time.sleep(5)

print("\n=== /api/commute/data-status ===")
code, body = get("/api/commute/data-status", timeout=45)
print(code)
try:
    j = json.loads(body)
    print(json.dumps(j, indent=2)[:2000])
except Exception:
    print(body[:600])

print("\n=== /api/commute/route (no auth) ===")
code, body = get("/api/commute/route?origin=Dhaka&destination=Gulistan", timeout=20)
print(code, body[:200])
