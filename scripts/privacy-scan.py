#!/usr/bin/env python3
"""Scan the exact Git payload and optional release archives without printing matched values."""
import argparse
from pathlib import Path
import re
import subprocess
import zipfile

RULES = {
    'personal-home-path': rb'/Users/[A-Za-z0-9_.-]+/',
    'windows-home-path': rb'[A-Z]:\\Users\\[A-Za-z0-9_.-]+\\',
    'private-key': rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',
    'github-token': rb'\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{30,})\b',
    'openai-project-key': rb'\bsk-(?:proj-|svcacct-)?[A-Za-z0-9_-]{40,}\b',
    'credential-file': rb'"(?:access_token|refresh_token|id_token)"\s*:\s*"[^"\s]{16,}"',
}
BLOCKED_NAMES = {'auth.json', '.DS_Store', '.env', 'history.json', 'state.json', 'worker.log'}

def inspect(name, data):
    errors=[]
    if Path(name).name in BLOCKED_NAMES:
        errors.append((name,'private-runtime-file'))
    for rule,pattern in RULES.items():
        if re.search(pattern,data): errors.append((name,rule))
    return errors

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive',action='append',default=[])
    args=parser.parse_args()
    files=subprocess.check_output(['git','ls-files','-z']).split(b'\0')
    errors=[]
    for raw in files:
        if raw:
            path=Path(raw.decode());errors.extend(inspect(str(path),path.read_bytes()))
    for path in args.archive:
        with zipfile.ZipFile(path) as bundle:
            for entry in bundle.infolist():
                if not entry.is_dir(): errors.extend(inspect(f'{Path(path).name}:{entry.filename}',bundle.read(entry)))
    for file,rule in errors: print(f'{file}: {rule}')
    if errors: raise SystemExit(1)
    print(f'PASS: {sum(bool(x) for x in files)} tracked files; {len(args.archive)} release archives')

if __name__=='__main__': main()
