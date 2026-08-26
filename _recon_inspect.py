import json
j = json.load(open('audit.json', encoding='utf-8'))
print('=== historical_conflicts ===')
for c in j['historical_conflicts']:
    print(' -', c if isinstance(c, str) else json.dumps(c))
print()
print('=== cleanup_candidates ===')
for c in j['cleanup_candidates']:
    print(' -', c if isinstance(c, str) else json.dumps(c))
print()
print('=== MISSING features (area=banned) ===')
for f in j['features']:
    if f['status'] == 'MISSING':
        print(f' area={f["area"]:8} name={f["name"]}')
print()
print('=== BACKEND_ONLY features ===')
for f in j['features']:
    if f['status'] == 'BACKEND_ONLY':
        print(f' area={f["area"]:8} name={f["name"]} | evidence={f["evidence"]}')
print()
print('=== BROKEN features ===')
for f in j['features']:
    if f['status'] == 'BROKEN':
        print(f' area={f["area"]:8} name={f["name"]} | evidence={f["evidence"]}')
print()
print('=== top_fixes ===')
for f in j.get('top_fixes', []):
    print(' -', f if isinstance(f, str) else json.dumps(f))
