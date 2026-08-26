"""
Verify actual CommuteBD live state on Render:
1. /api/commute/data-status — table counts (15 tables expected)
2. /api/commute/route — does it return real legs or empty?
3. /api/commute/fare-report — does dedupe_key column exist?

Without auth tokens (test endpoints) we can only check the unauthenticated ones.
"""
import urllib.request, json, ssl

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

def get(path):
    url = f"https://ekthikana-api-x473.onrender.com{path}"
    req = urllib.request.Request(url, method="GET")
    req.add_header("Accept", "application/json")
    try:
        r = urllib.request.urlopen(req, context=ctx, timeout=15)
        return r.status, r.read().decode("utf-8")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", errors="replace")
    except Exception as e:
        return -1, str(e)

print("=== /api/commute/data-status ===")
code, body = get("/api/commute/data-status")
print(code)
try:
    j = json.loads(body)
    print(json.dumps(j, indent=2)[:1500])
except Exception:
    print(body[:500])

print("\n=== /api/commute/route (no auth, expect 401) ===")
code, body = get("/api/commute/route?origin=Dhaka&destination=Gulistan")
print(code, body[:300])
