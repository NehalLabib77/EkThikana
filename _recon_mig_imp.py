import re

# Migration
sql = open('backend/migrations/001_gochano_commutebd_production.sql', encoding='utf-8').read()
print('=== migration file ===')
print('length:', len(sql))
print('first 80 lines:')
for i, line in enumerate(sql.splitlines()[:80], 1):
    print(f'  {i:3} {line}')

print('\n=== detect any "create table" with flexible whitespace ===')
# try regex with flexible whitespace
hits = re.findall(r'create\s+table\s+[^(]*', sql, re.IGNORECASE)
print('raw matches:', hits[:20])

print('\n=== all table-name-like tokens ===')
# look for backticks/quoted identifiers
hits2 = re.findall(r'"([a-zA-Z_][a-zA-Z0-9_]*)"', sql)
print('quoted:', sorted(set(hits2)))
