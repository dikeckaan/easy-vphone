#!/usr/bin/env python3
"""Version-guarded, idempotent runtime compatibility fixes."""
import hashlib
from pathlib import Path
import shutil
import sys

EXPECTED = {
    'cfw_patch_xpc_lwcr.py': '22d467a70c3f5f03758faa8b23b7faf41fa5bf57add65eb0a258998774ba3730',
    'cfw_patch_lockdown_mode.py': '28bc8b25a085b9ea753d8ec684d85ff8a114dcf44995f2b1c32b2918e2e5f1ca',
}
MARKER = 'PROJ="${SCRIPT_DIR:h}"'
ADDITION = '\n[[ ! -f "$PROJ/developer-dir" ]] || export DEVELOPER_DIR="$(cat "$PROJ/developer-dir")"'


def prepare(source, runtime):
    source, runtime = Path(source), Path(runtime)
    host = runtime / 'scripts/cfw_install_host.sh'
    script = host.read_text()
    if ADDITION not in script and MARKER not in script:
        raise ValueError('Upstream CFW script changed; SDK patch cannot be applied safely.')
    changes = []
    # Validate every patch before writing any file.
    for name, expected in EXPECTED.items():
        incoming = (source / name).read_bytes()
        target = runtime / 'scripts/patchers' / name
        current = target.read_bytes()
        if current == incoming:
            continue
        if hashlib.sha256(current).hexdigest() != expected:
            raise ValueError('Upstream patcher changed; refusing to overwrite unknown code: ' + name)
        changes.append((source / name, target))
    if ADDITION not in script:
        host.write_text(script.replace(MARKER, MARKER + ADDITION, 1))
    for src, dst in changes:
        shutil.copy2(src, dst)

if __name__ == '__main__':
    try:
        prepare(*sys.argv[1:])
    except (OSError, ValueError, TypeError) as exc:
        raise SystemExit(str(exc))
