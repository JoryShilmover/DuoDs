#!/usr/bin/env python3
"""Retrieve exact source revisions. Never overwrite a different/dirty checkout."""
import json, subprocess
from pathlib import Path
root=Path(__file__).resolve().parent.parent
for dep in json.loads((root/'Dependencies/lock.json').read_text())['dependencies']:
    path=root/dep['path']; path.parent.mkdir(parents=True,exist_ok=True)
    if not path.exists():
        subprocess.run(['git','clone','--no-checkout',dep['url'],str(path)],check=True)
        subprocess.run(['git','-C',str(path),'checkout','--detach',dep['commit']],check=True)
    revision=subprocess.check_output(['git','-C',str(path),'rev-parse','HEAD'],text=True).strip()
    if revision != dep['commit']: raise SystemExit(f'Revision mismatch at {path}; preserve it and resolve manually.')
core=root/'build/dependencies/melonds-ds'
patch=root/'Dependencies/patches/static-core.patch'
if subprocess.run(['git','-C',str(core),'apply','--reverse','--check',str(patch)],capture_output=True).returncode:
    subprocess.run(['git','-C',str(core),'apply','--check',str(patch)],check=True)
    subprocess.run(['git','-C',str(core),'apply',str(patch)],check=True)
actual=subprocess.check_output(['git','-C',str(core),'diff'],text=True)
if actual != patch.read_text(): raise SystemExit('Core local diff differs from retained patch; refusing unrecorded source changes.')
# Upstream zlib's out-of-source configure renames this tracked header. Restore
# only that exact mechanically moved file, checking it against the pinned blob.
zlib=root/'build/dependencies/fetched/zlib-src'
if not (zlib/'zconf.h').exists() and (zlib/'zconf.h.included').exists():
    expected=subprocess.check_output(['git','-C',str(zlib),'show','HEAD:zconf.h'])
    if (zlib/'zconf.h.included').read_bytes()==expected:
        (zlib/'zconf.h.included').rename(zlib/'zconf.h')
for dep in json.loads((root/'Dependencies/lock.json').read_text())['dependencies'][1:]:
    if subprocess.check_output(['git','-C',str(root/dep['path']),'status','--porcelain'],text=True).strip():
        raise SystemExit('Dirty dependency: '+dep['name'])
print('All dependency revisions and core patch verified.')
