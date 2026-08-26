spec = open('PROJECT_SPEC.md', encoding='utf-8').read()
import re
keywords = ['chat', 'chatEnabled', 'focus', 'streak', 'docx', 'DOCX', 'offline', 'monthly money',
            'remaining money', 'available money', 'completed task', 'study time', 'pomodoro',
            'monthly available', 'monthly limit', 'remaining', 'mcq', 'quiz', 'rentmate',
            'wellness', 'savings', 'cash-flow', 'community library', 'public sharing',
            'family hub', 'familyhub', 'admin toggle', 'general account']
for kw in keywords:
    hits = [l.strip() for l in spec.splitlines() if kw.lower() in l.lower()]
    if hits:
        print(f'\n[{kw}]')
        for h in hits[:4]:
            print(f'  {h[:200]}')
print('\n--- last 60 lines of spec ---')
print('\n'.join(spec.splitlines()[-60:]))