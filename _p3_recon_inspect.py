"""Inspect audit.json feature status distribution for PART 3 reconciliation."""
import json
from collections import Counter
from pathlib import Path

ROOT = Path(r"D:\EkThikana_Full_Production_Starter")
d = json.loads((ROOT / "audit.json").read_text(encoding="utf-8"))

c = Counter(f.get("status", "?") for f in d["features"])
print("STATUS DISTRIBUTION (features[]):")
for k, v in sorted(c.items(), key=lambda x: -x[1]):
    print(f"  {k}: {v}")
print()

for status in ("MISSING", "NEEDS_LIVE_TEST", "PARTIAL", "WORKING", "UI_ONLY", "BACKEND_ONLY", "BROKEN", "UNUSED_DEAD"):
    items = [(i, f) for i, f in enumerate(d["features"]) if f.get("status") == status]
    print(f"=== {status} ({len(items)}) ===")
    for i, f in items:
        print(f"  [{i}] area={f.get('area')}  name={f.get('name')}")
    print()
