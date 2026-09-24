#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode-Beta.app ]]; then
  export DEVELOPER_DIR=/Applications/Xcode-Beta.app/Contents/Developer
fi
exec python3 scripts/build-poc.py "$@"
