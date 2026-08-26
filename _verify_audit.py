import json

d = json.load(open(r'd:\EkThikana_Full_Production_Starter\audit.json', encoding='utf-8'))

print('=== Spec compliance checks ===')
features = d['features']
print(f'len(features) == 62: {len(features) == 62}')

obsolete_removed = [f['name'] for f in features if f.get('status') == 'OBSOLETE_REMOVED']
print(f'No OBSOLETE_REMOVED in features: {len(obsolete_removed) == 0}')

drop_check = ['Register (dual role)', 'Tasks (general only)', 'Community Library']
print('Drops present in features:', [n for n in drop_check if any(f['name'] == n for f in features)])

names = [f['name'] for f in features]
dup = [n for n in set(names) if names.count(n) > 1]
print(f'Duplicate names in features: {dup}')

counts = d['counts']
state_sum = sum(counts[k] for k in ('WORKING','PARTIAL','UI_ONLY','BACKEND_ONLY','BROKEN','MISSING','UNUSED_DEAD','NEEDS_LIVE_TEST'))
print(f'8-state sum: {state_sum} == features_total: {counts["features_total"]}: {state_sum == counts["features_total"]}')
print('Counts:',
      'WORKING=' + str(counts["WORKING"]),
      'PARTIAL=' + str(counts["PARTIAL"]),
      'UI_ONLY=' + str(counts["UI_ONLY"]),
      'BACKEND_ONLY=' + str(counts["BACKEND_ONLY"]),
      'BROKEN=' + str(counts["BROKEN"]),
      'MISSING=' + str(counts["MISSING"]),
      'UNUSED_DEAD=' + str(counts["UNUSED_DEAD"]),
      'NEEDS_LIVE_TEST=' + str(counts["NEEDS_LIVE_TEST"]))
print('total_audited = features+dead_code+obsolete:', counts["total_audited"])

print('git_safety present:', 'git_safety' in d)
print('GEMINI status preserved:', d['integration_verdicts']['GEMINI']['status'])

hc = d['historical_conflicts']
print('historical_conflicts:', len(hc), 'entries')
for h in hc:
    print('  -', h.get('name') or h.get('conflict'))

hist_count = sum(1 for c in d['control_audit'] if c.get('historical_period') == 'PART1_HISTORICAL')
print('control_audit with PART1_HISTORICAL:', hist_count)