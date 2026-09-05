import pathlib

files = [
    'firebase/firestore.rules',
    'flutter_app/lib/features/auth/presentation/login_screen.dart',
    'flutter_app/lib/features/life/presentation/expense/grocery_tab.dart',
]

for f in files:
    p = pathlib.Path(f)
    raw = p.read_bytes()
    # Check for mixed line endings
    crlf = raw.count(b'\r\n')
    # Count lines with trailing whitespace
    text = raw.decode('utf-8')
    lines = text.split('\n')
    trailing_count = 0
    for i, line in enumerate(lines):
        rstripped = line.rstrip('\r')
        if rstripped != line.rstrip():
            trailing_count += 1
            if trailing_count <= 5:
                print(f'  {f}:{i+1}: trailing CR or space detected: {line[:80]!r}')
    print(f'{f}: CRLF={crlf}, lines_with_trailing={trailing_count}, total_lines={len(lines)}')
    
    # Now fix: strip trailing whitespace from each line
    cleaned_lines = []
    for line in lines:
        # Strip trailing spaces and tabs, then trailing CR if present
        stripped = line.rstrip(' \t\r')
        cleaned_lines.append(stripped)
    
    result = '\n'.join(cleaned_lines)
    # Restore CRLF line endings
    result = result.replace('\n', '\r\n')
    p.write_bytes(result.encode('utf-8'))
    print(f'  -> Fixed')

print('Done')
