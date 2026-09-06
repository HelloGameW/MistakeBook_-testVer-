#!/bin/bash
set -euo pipefail
PROJECT_ROOT=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$PROJECT_ROOT/build/logs"
xcrun simctl list devices available --json > "$PROJECT_ROOT/build/simulators.json"
SIMULATOR_ID=$(python3 - "$PROJECT_ROOT/build/simulators.json" <<'PY'
import json, re, sys
with open(sys.argv[1]) as source:
    devices = json.load(source)["devices"]
candidates = []
for runtime, entries in devices.items():
    version = re.search(r'iOS-(\d+)-(\d+)', runtime)
    if not version or int(version[1]) < 26:
        continue
    for device in entries:
        if device.get("isAvailable") and device["name"].startswith("iPhone"):
            candidates.append(((int(version[1]), int(version[2])), device["udid"]))
if not candidates:
    sys.exit("No available iPhone simulator with iOS 26 or newer; install its runtime in Xcode.")
print(sorted(candidates)[-1][1])
PY
)
xcodebuild test \
  -project "$PROJECT_ROOT/MistakeBook.xcodeproj" \
  -scheme MistakeBook -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  -derivedDataPath "$PROJECT_ROOT/build/simulator" \
  -resultBundlePath "$PROJECT_ROOT/build/tests-$(date +%Y%m%d-%H%M%S).xcresult" \
  CODE_SIGNING_ALLOWED=NO \
  2>&1 | tee "$PROJECT_ROOT/build/logs/simulator-tests.log"
