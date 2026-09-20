#!/bin/bash
# Build the iPhone app. Usage: scripts/ios.sh [build|run]
#   build  compile for the simulator, unsigned (the default)
#   run    compile, boot a simulator, install and launch
# Installing on a real iPhone needs your signing team, so that goes through Xcode:
#   open ios/Lyra.xcodeproj
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

project=ios/Lyra.xcodeproj
common=(-project "$project" -scheme Lyra -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO)

set -o pipefail
xcodebuild "${common[@]}" build | grep -E 'error:|BUILD' || {
  status=$?
  # grep found nothing to print (1) is fine; anything else is xcodebuild failing.
  [[ $status -eq 1 ]] || exit $status
}

[[ "${1:-build}" == "run" ]] || exit 0

app="$(xcodebuild "${common[@]}" -showBuildSettings 2>/dev/null |
  awk -F' = ' '/ BUILT_PRODUCTS_DIR/{print $2; exit}')/Lyra.app"
[[ -d "$app" ]] || { echo "Built app not found at $app" >&2; exit 1; }

device="$(xcrun simctl list devices available -j |
  python3 -c 'import json,sys
devices = json.load(sys.stdin)["devices"]
phones = [d for runtime in devices.values() for d in runtime if "iPhone" in d["name"]]
print(next((d["udid"] for d in phones if d["state"] == "Booted"), phones[0]["udid"] if phones else ""))')"
[[ -n "$device" ]] || { echo 'No iPhone simulator is available. Add one in Xcode → Settings → Components.' >&2; exit 1; }

xcrun simctl boot "$device" 2>/dev/null || true

# The window that shows a booted simulator: Simulator.app up to Xcode 26, DeviceHub.app after.
# Neither is needed to install or launch, so a missing one is not a failure.
developer="${DEVELOPER_DIR:-$(xcode-select -p)}"
for gui in "$developer/Applications/Simulator.app" "$developer/../Applications/DeviceHub.app"; do
  [[ -d "$gui" ]] && { open "$gui"; break; }
done

xcrun simctl install "$device" "$app"
xcrun simctl launch "$device" local.lyra.phone
printf 'Running on simulator %s\n' "$device"
