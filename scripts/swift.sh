#!/bin/bash
# A process-local workaround for remnants of old Apple Command Line Tools installs.
# No files in /Library/Developer are changed.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
python3 - <<'PY'
import json, pathlib, subprocess
base = pathlib.Path(subprocess.check_output(['xcode-select', '-p'], text=True).strip())
root = pathlib.Path('.build').resolve()
entries = []
old = base / 'usr/include/swift/module.modulemap'
new = base / 'usr/include/swift/bridging.modulemap'
if old.exists() and new.exists() and 'module SwiftBridging' in old.read_text() and 'module SwiftBridging' in new.read_text():
    empty = root / 'empty.modulemap'
    empty.write_text('// Duplicate legacy module map omitted from this build.\n')
    entries.append({'type': 'file', 'name': str(old), 'external-contents': str(empty)})
for private in (base / 'usr/lib/swift/pm/ManifestAPI').glob('*.swiftmodule/*.private.swiftinterface'):
    public = private.with_name(private.name.replace('.private.swiftinterface', '.swiftinterface'))
    if public.exists() and public.stat().st_mtime - private.stat().st_mtime > 86400:
        entries.append({'type': 'file', 'name': str(private), 'external-contents': str(public)})
(root / 'toolchain-overlay.json').write_text(json.dumps({'version': 0, 'roots': entries}))
if entries:
    print(f'Using {len(entries)} local toolchain overlays; system files are unchanged.')
PY
export SWIFT_EXEC="$PWD/scripts/swiftc-local.sh"
exec /usr/bin/swift "$@"
