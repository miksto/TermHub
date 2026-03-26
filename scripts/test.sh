#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

for scheme in TermHub TermHubMCP; do
  echo "=== Testing $scheme ==="
  xcodebuild \
    -workspace TermHub.xcodeproj/project.xcworkspace \
    -scheme "$scheme" \
    -configuration Debug \
    test 2>&1 \
    | grep -E '(Test Case|Tests? (passed|failed)|warning:|error:|BUILD FAILED|Executed|[◇✔✘↳⚠] )' \
    || echo "Tests completed"
done
