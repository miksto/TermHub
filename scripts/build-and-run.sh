#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Build and capture the derived data path
BUILD_DIR=$(xcodebuild \
  -project TermHub.xcodeproj \
  -scheme TermHub \
  -configuration Debug \
  -showBuildSettings 2>/dev/null \
  | grep -m1 'BUILT_PRODUCTS_DIR' \
  | awk '{print $3}')

# Build
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

# Launch the app
APP_PATH="$BUILD_DIR/TermHub.app"
if [ -d "$APP_PATH" ]; then
  echo "Launching $APP_PATH"
  open "$APP_PATH"
else
  echo "ERROR: App not found at $APP_PATH"
  exit 1
fi
