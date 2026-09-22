#!/usr/bin/env python3
"""Owner-side traffic collector. Uses gh's existing login, never exports tokens."""
import importlib.util
from pathlib import Path
import os
import subprocess
import tempfile

REPO = 'https://github.com/dikeckaan/easy-vphone.git'
ENV = dict(os.environ, PATH='/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin', GIT_TERMINAL_PROMPT='0')

def run(args,cwd=None):
    return subprocess.run(args,cwd=cwd,env=ENV,check=True,timeout=120)

def main():
    spec=importlib.util.spec_from_file_location('metrics',Path(__file__).with_name('metrics.py'))
    metrics=importlib.util.module_from_spec(spec); spec.loader.exec_module(metrics)
    import json
    for attempt in range(3):
        # Isolated disposable clone: never resets or changes the user's checkout.
        with tempfile.TemporaryDirectory(prefix='easy-vphone-metrics-') as directory:
            root=Path(directory)/'repo'
            run(['git','clone','--depth','1',REPO,str(root)])
            path=root/'metrics/data.json'
            previous=json.loads(path.read_text()) if path.exists() else {}
            data=metrics.collect(previous)
            if 'clones_error' in data or 'views_error' in data:
                raise RuntimeError('Existing gh login cannot read traffic; check repository access.')
            metrics.render(data,root)
            run(['git','config','user.name','easy-vphone metrics'],root)
            run(['git','config','user.email','dikeckaan@users.noreply.github.com'],root)
            run(['git','add','README.md','METRICS.md','metrics/data.json'],root)
            unchanged=subprocess.run(['git','diff','--cached','--quiet'],cwd=root,env=ENV).returncode == 0
            if unchanged: return
            run(['git','commit','-m','Refresh owner traffic snapshot [skip ci]'],root)
            try:
                run(['git','-c','credential.helper=','-c','credential.helper=!gh auth git-credential','push',REPO,'HEAD:main'],root)
                return
            except subprocess.CalledProcessError:
                if attempt == 2: raise
                # A concurrent Actions update won. Re-read its snapshot and retry.

if __name__=='__main__':
    os.environ.update(ENV)
    main()
