#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

pattern='(Test Case|Tests? (passed|failed)|warning:|error:|BUILD FAILED|Executed|[◇✔✘↳⚠] )'

for scheme in TermHub TermHubMCP; do
  echo "=== Testing $scheme ==="
  log_file="$(mktemp)"
  if ! xcodebuild \
    -project TermHub.xcodeproj \
    -scheme "$scheme" \
    -configuration Debug \
    test >"$log_file" 2>&1; then
    grep -E "$pattern" "$log_file" || true
    rm -f "$log_file"
    exit 1
  fi

  grep -E "$pattern" "$log_file" || echo "Tests completed"
  rm -f "$log_file"
done
