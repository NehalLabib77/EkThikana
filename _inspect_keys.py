import json, re
with open(r'd:\EkThikana_Full_Production_Starter\audit.json') as f:
    data = json.load(f)
print("TOP-LEVEL KEYS:")
for k in data.keys():
    if isinstance(data[k], dict):
        print(f"  {k}: dict ({len(data[k])} keys)")
    elif isinstance(data[k], list):
        print(f"  {k}: list ({len(data[k])} items)")
    else:
        print(f"  {k}: {type(data[k]).__name__} = {data[k]}")