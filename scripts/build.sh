#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

xcodebuild \
  -workspace TermHub.xcodeproj/project.xcworkspace \
  -scheme TermHub \
  -configuration Debug \
  build 2>&1 \
  | grep -E '(warning:|error:|BUILD SUCCEEDED|BUILD FAILED|fatal)' \
  || echo "Build completed with no issues"
