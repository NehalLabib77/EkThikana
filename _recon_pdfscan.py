import re
text = open('backend/app/routers/materials.py', encoding='utf-8').read()
print('len:', len(text))
for kw in ['pdf', 'docx', '.doc', 'mimetype', 'allowed', 'content_type']:
    hits = [(i+1, l.strip()) for i, l in enumerate(text.splitlines()) if kw in l.lower()]
    print(f'\n[{kw}] {len(hits)} hits')
    for ln, l in hits[:5]:
        print(f'  {ln}: {l[:140]}')
