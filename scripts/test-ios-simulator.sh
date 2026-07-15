#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/TestHost/AEMotionTestHost.xcodeproj"
RESULTS_DIR="${RESULTS_DIR:-$ROOT_DIR/build/TestHostResults}"
RESULT_BUNDLE="$RESULTS_DIR/AEMotionTestHost.xcresult"
DERIVED_DATA="$RESULTS_DIR/DerivedData"
LOG_FILE="$RESULTS_DIR/xcodebuild.log"

bash "$ROOT_DIR/scripts/generate-test-host.sh"
mkdir -p "$RESULTS_DIR"
rm -rf "$RESULT_BUNDLE" "$DERIVED_DATA"

SIMULATOR_UDID="${IOS_SIMULATOR_UDID:-}"
if [[ -z "$SIMULATOR_UDID" ]]; then
  SIMULATOR_UDID="$(xcrun simctl list devices available -j | python3 -c '
import json
import sys

data = json.load(sys.stdin)
for runtime in sorted(data.get("devices", {}), reverse=True):
    for device in data["devices"][runtime]:
        if device.get("isAvailable") and device.get("name", "").startswith("iPhone"):
            print(device["udid"])
            raise SystemExit(0)
raise SystemExit(1)
')"
fi

if [[ -z "$SIMULATOR_UDID" ]]; then
  echo "error: No available iPhone Simulator was found." >&2
  exit 1
fi

echo "Using iPhone Simulator: $SIMULATOR_UDID"

command=(
  xcodebuild test
  -project "$PROJECT_PATH"
  -scheme AEMotionTestHost
  -destination "platform=iOS Simulator,id=$SIMULATOR_UDID"
  -derivedDataPath "$DERIVED_DATA"
  -resultBundlePath "$RESULT_BUNDLE"
  CODE_SIGNING_ALLOWED=NO
)

set -o pipefail
if command -v xcbeautify >/dev/null 2>&1; then
  "${command[@]}" 2>&1 | tee "$LOG_FILE" | xcbeautify
else
  "${command[@]}" 2>&1 | tee "$LOG_FILE"
fi

echo "Test result bundle: $RESULT_BUNDLE"
