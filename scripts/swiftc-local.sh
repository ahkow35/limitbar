#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEVELOPER_ROOT="$(xcode-select -p)"
OVERLAY="$ROOT/.build/toolchain-overlay.json"
if [[ -f "$OVERLAY" ]]; then
    exec /usr/bin/swiftc "$@" -vfsoverlay "$OVERLAY" -Xcc -ivfsoverlay -Xcc "$OVERLAY" -module-cache-path "$ROOT/.build/ModuleCache-local" -F "$DEVELOPER_ROOT/Library/Developer/Frameworks" -Xlinker -rpath -Xlinker "$DEVELOPER_ROOT/Library/Developer/Frameworks"
else
    exec /usr/bin/swiftc "$@"
fi
