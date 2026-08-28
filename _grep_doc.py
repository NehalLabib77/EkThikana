import sys
with open(r'd:\EkThikana_Full_Production_Starter\GOCHANO.md', 'r', encoding='utf-8') as f:
    lines = f.readlines()
print(f"Total lines: {len(lines)}")
# Find "gochano_logo" references
for i, l in enumerate(lines):
    if 'gochano_logo' in l or 'Gochano.png' in l:
        print(f"{i+1}: {l.rstrip()}")
print("---")
# Find §23
for i, l in enumerate(lines):
    if 'Animated Flutter splash' in l or 'gochano_splash_screen' in l or 'gochano_loading' in l:
        print(f"{i+1}: {l.rstrip()}")