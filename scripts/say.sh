#!/bin/bash
# Send a typed command to the running Lyra app. Usage: scripts/say.sh "Open Finder"
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
mkdir -p mac/.build
if [[ ! -x mac/.build/say || scripts/say.swift -nt mac/.build/say ]]; then
  xcrun swiftc -O scripts/say.swift -o mac/.build/say
fi
mac/.build/say "$@"
