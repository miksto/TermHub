#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

xcodebuild \
  -workspace TermHub.xcodeproj/project.xcworkspace \
  -scheme TermHub \
  -configuration Debug \
  test 2>&1 \
  | grep -E '(Test Case|Tests? (passed|failed)|warning:|error:|BUILD FAILED|Executed|[◇✔✘↳⚠] )' \
  || echo "Tests completed"
