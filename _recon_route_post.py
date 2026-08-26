import urllib.request, json, ssl, urllib.error
ctx = ssl.create_default_context(); ctx.check_hostname=False; ctx.verify_mode=ssl.CERT_NONE

req = urllib.request.Request(
    'https://ekthikana-api-x473.onrender.com/api/commute/route',
    method='POST',
    data=b'{}',
    headers={'Content-Type': 'application/json', 'Accept': 'application/json'},
)
try:
    r = urllib.request.urlopen(req, context=ctx, timeout=30)
    print('POST no-auth:', r.status, r.read().decode()[:200])
except urllib.error.HTTPError as e:
    print('POST no-auth:', e.code, e.read().decode()[:300])
except Exception as e:
    print('POST error:', e)
