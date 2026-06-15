#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate
xcode-build-server config -project TermHub.xcodeproj -scheme TermHub
