#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Build and capture the derived data path
BUILD_DIR=$(xcodebuild \
  -workspace TermHub.xcodeproj/project.xcworkspace \
  -scheme TermHub \
  -configuration Debug \
  -showBuildSettings 2>/dev/null \
  | grep -m1 'BUILT_PRODUCTS_DIR' \
  | awk '{print $3}')

# Build
xcodebuild \
  -workspace TermHub.xcodeproj/project.xcworkspace \
  -scheme TermHub \
  -configuration Debug \
  build 2>&1 \
  | grep -E '(warning:|error:|BUILD SUCCEEDED|BUILD FAILED|fatal)' \
  || echo "Build completed with no issues"

# Launch the app
APP_PATH="$BUILD_DIR/TermHub.app"
if [ -d "$APP_PATH" ]; then
  echo "Launching $APP_PATH"
  open "$APP_PATH"
else
  echo "ERROR: App not found at $APP_PATH"
  exit 1
fi
