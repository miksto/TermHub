#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

if output=$(
  xcodebuild \
    -project TermHub.xcodeproj \
    -scheme TermHub \
    -configuration Debug \
    build 2>&1
); then
  status=0
else
  status=$?
fi

printf '%s\n' "$output" | grep -E '(warning:|error:|BUILD SUCCEEDED|BUILD FAILED|fatal)' || true

if [ $status -ne 0 ]; then
  exit $status
fi

if ! printf '%s\n' "$output" | grep -qE '(warning:|error:|BUILD SUCCEEDED|BUILD FAILED|fatal)'; then
  echo "Build completed with no issues"
fi
