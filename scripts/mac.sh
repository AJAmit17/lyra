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

running() { pgrep -x Lyra >/dev/null; }
if running; then
  echo 'Quit Lyra before building and installing.' >&2
  exit 1
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
  echo 'Lyra was opened during the build. Quit it, then build again.' >&2
  exit 1
fi
mkdir -p "$HOME/Applications"
ditto "$staged" "$installed"
codesign --verify --strict "$installed"
printf 'Installed: %s\n' "$installed"

if [[ "${1:-}" == "--run" ]]; then
  open "$installed"
  printf 'Running.\n'
fi
