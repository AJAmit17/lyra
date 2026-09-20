#!/bin/bash
# Build the macOS app, sign it locally, install it into ~/Applications.
# Usage: scripts/mac.sh [--run]
set -euo pipefail
cd "$(dirname "$0")/.."

# Use the installed Xcode for XCTest and the native SDKs, without changing xcode-select.
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
if [[ ! -d "${DEVELOPER_DIR:-/nonexistent}" ]]; then
  echo 'Xcode is required: Command Line Tools alone cannot build SwiftUI or XCTest.' >&2
  exit 1
fi

# A running copy holds the app bundle open, so stop it rather than refusing to build.
running() { pgrep -x Lyra >/dev/null; }
was_running=false
if running; then
  was_running=true
  echo 'Quitting the running Lyra…'
  osascript -e 'quit app "Lyra"' >/dev/null 2>&1 || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do running || break; sleep 0.3; done
  running && pkill -x Lyra 2>/dev/null || true
  for _ in 1 2 3 4 5; do running || break; sleep 0.3; done
  if running; then
    echo 'Lyra will not quit. Close it from the menu bar icon, then build again.' >&2
    exit 1
  fi
fi

xcrun swift build --package-path mac -c release
bin="$(xcrun swift build --package-path mac -c release --show-bin-path)"
staged="mac/.build/app/Lyra.app"
installed="$HOME/Applications/Lyra.app"

rm -rf "$staged"
mkdir -p "$staged/Contents/MacOS" "$staged/Contents/Resources"
cp "$bin/Lyra" "$staged/Contents/MacOS/Lyra"
cp mac/Resources/Info.plist "$staged/Contents/Info.plist"
cp mac/Resources/Lyra.icns "$staged/Contents/Resources/Lyra.icns"
python3 scripts/sign-local.py "$staged"

if running; then
  osascript -e 'quit app "Lyra"' >/dev/null 2>&1 || true
  for _ in 1 2 3 4 5; do running || break; sleep 0.3; done
fi
mkdir -p "$HOME/Applications"
ditto "$staged" "$installed"
codesign --verify --strict "$installed"
printf 'Installed: %s\n' "$installed"

if [[ "${1:-}" == "--run" || "$was_running" == true ]]; then
  open "$installed"
  printf 'Running.\n'
fi
