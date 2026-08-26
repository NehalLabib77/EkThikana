import json, pathlib
j = json.loads(pathlib.Path('audit.json').read_text(encoding='utf-8'))
pathlib.Path('.part3_git_safety_original.json').write_text(
    json.dumps(j['git_safety'], indent=2, sort_keys=True) + '\n', encoding='utf-8')
print('snapshot bytes:', pathlib.Path('.part3_git_safety_original.json').stat().st_size)
print('current git_safety keys:', list(j['git_safety'].keys()))