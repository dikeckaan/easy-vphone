#!/usr/bin/env python3
"""Install the owner's local aggregate traffic collector, without copying credentials."""
from pathlib import Path
import plistlib
import shutil
import subprocess
import os

root=Path(__file__).resolve().parents[1]
base=Path.home()/'Library/Application Support/easy-vphone-metrics'
base.mkdir(parents=True,exist_ok=True)
for name in ('metrics.py','publish-metrics.py'):
    shutil.copyfile(root/'scripts'/name,base/name)
python=shutil.which('python3')
if not python: raise SystemExit('Python 3 required')
agent=Path.home()/'Library/LaunchAgents/io.github.easy-vphone.metrics.plist'
agent.parent.mkdir(parents=True,exist_ok=True)
label='io.github.easy-vphone.metrics'
value={'Label':label,'ProgramArguments':[python,str(base/'publish-metrics.py')],
       'RunAtLoad':True,'StartInterval':21600,
       'EnvironmentVariables':{'PATH':'/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin'},
       'StandardOutPath':str(base/'collector.log'),'StandardErrorPath':str(base/'collector.log')}
agent.write_bytes(plistlib.dumps(value))
# Reload this application's own agent when already installed.
subprocess.run(['launchctl','bootout',f'gui/{os.getuid()}/{label}'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
subprocess.run(['launchctl','bootstrap',f'gui/{os.getuid()}',str(agent)],check=True)
print('Installed six-hour owner metrics collector:',agent)
