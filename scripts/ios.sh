#!/bin/bash
# Build the iPhone app. Usage: scripts/ios.sh [build|run|device]
#   build   compile for the simulator, unsigned (the default)
#   run     compile, boot a simulator, install and launch
#   device  build signed and install onto the iPhone plugged in over USB
#
# `device` needs an Apple ID signed into Xcode (Settings -> Accounts). A free one is enough:
# it gives a personal team, and the app then runs for seven days before it needs reinstalling.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

project=ios/Lyra.xcodeproj

if [[ "${1:-build}" == "device" ]]; then
  udid="$(xcrun devicectl list devices 2>/dev/null |
    awk '/physical/ && /connected/ {for (i = 1; i <= NF; i++) if ($i ~ /^[0-9A-F-]{24,}$/) {print $i; exit}}')"
  if [[ -z "$udid" ]]; then
    echo 'No iPhone is connected. Plug it in, unlock it, and tap Trust on the phone.' >&2
    exit 1
  fi

  # Xcode records the teams for every signed-in Apple ID here. `defaults` exits non-zero when
  # nobody has signed in, which is the case this branch exists to explain, so do not let it abort.
  # Xcode 27 keys this by account identifier; older versions used IDEProvisioningTeams. The value
  # is unquoted for a personal team and quoted for some others, so accept both.
  team="${DEVELOPMENT_TEAM:-}"
  if [[ -z "$team" ]]; then
    for key in IDEProvisioningTeamByIdentifier IDEProvisioningTeams; do
      team="$(defaults read com.apple.dt.Xcode "$key" 2>/dev/null |
        sed -n 's/.*teamID = "\{0,1\}\([A-Z0-9]\{10\}\)"\{0,1\};.*/\1/p' | head -1 || true)"
      [[ -n "$team" ]] && break
    done
  fi
  if [[ -z "$team" ]]; then
    cat >&2 <<'HINT'
No Apple ID is signed into Xcode, so the app cannot be signed for a real phone.

  1. Xcode -> Settings -> Accounts -> + -> Apple ID, and sign in. A free account works.
  2. On the iPhone: Settings -> Privacy & Security -> Developer Mode -> on, then restart it.
  3. Run this again.

To use a specific team: DEVELOPMENT_TEAM=XXXXXXXXXX scripts/ios.sh device
HINT
    exit 1
  fi

  echo "Signing with team $team for device $udid"
  xcodebuild -project "$project" -scheme Lyra -configuration Debug \
    -destination "id=$udid" -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$team" \
    build | grep -E 'error:|BUILD' || {
      status=$?
      [[ $status -eq 1 ]] || exit $status
    }

  app="$(xcodebuild -project "$project" -scheme Lyra -configuration Debug \
    -destination "id=$udid" DEVELOPMENT_TEAM="$team" -showBuildSettings 2>/dev/null |
    awk -F' = ' '/ BUILT_PRODUCTS_DIR/{print $2; exit}')/Lyra.app"
  [[ -d "$app" ]] || { echo "Built app not found at $app" >&2; exit 1; }

  xcrun devicectl device install app --device "$udid" "$app"
  echo
  echo "Installed on $udid."

  # A free personal team's certificate is untrusted until the owner says otherwise on the phone,
  # so the first launch after a fresh certificate always fails here. Say what to do about it.
  if ! xcrun devicectl device process launch --device "$udid" local.lyra.phone >/dev/null 2>&1; then
    cat <<'TRUST'

It will not open yet: the developer certificate is not trusted on the phone.

  On the iPhone: Settings -> General -> VPN & Device Management
                 -> Apple Development: <your Apple ID> -> Trust

Then tap Lyra on the home screen, or run this again.
TRUST
  else
    echo 'Launched.'
  fi
  exit 0
fi

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
