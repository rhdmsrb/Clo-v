#!/bin/bash
set -euo pipefail

# Build this worktree and install it on the specified booted simulator.
# Usage: scripts/run-simulator.sh SIMULATOR_UUID [--sample]
if [[ $# -lt 1 || $# -gt 2 || (${2:-} != "" && ${2:-} != "--sample") ]]; then
    echo "Usage: $0 SIMULATOR_UUID [--sample]" >&2
    exit 2
fi
simulator_id=$1
script_dir=$(cd "$(dirname "$0")" && pwd)
repo_dir=$(cd "$script_dir/.." && pwd)
cd "$repo_dir"

xcrun simctl bootstatus "$simulator_id" -b
xcodebuild -project CLOV.xcodeproj -scheme CLOV \
    -destination "platform=iOS Simulator,id=$simulator_id" \
    -derivedDataPath .build/dd build CODE_SIGNING_ALLOWED=NO
xcrun simctl terminate "$simulator_id" com.clov.app >/dev/null 2>&1 || true
xcrun simctl install "$simulator_id" .build/dd/Build/Products/Debug-iphonesimulator/CLOV.app
if [[ ${2:-} == "--sample" ]]; then
    xcrun simctl launch "$simulator_id" com.clov.app --uiTestSampleData
else
    xcrun simctl launch "$simulator_id" com.clov.app
fi
