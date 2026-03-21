#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate
xcode-build-server config -workspace TermHub.xcodeproj/project.xcworkspace -scheme TermHub
