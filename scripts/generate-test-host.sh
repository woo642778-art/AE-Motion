#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_HOST_DIR="$ROOT_DIR/TestHost"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "error: XcodeGen is required. Install it with: brew install xcodegen" >&2
  exit 1
fi

xcodegen generate \
  --spec "$TEST_HOST_DIR/project.yml" \
  --project "$TEST_HOST_DIR"

echo "Generated $TEST_HOST_DIR/AEMotionTestHost.xcodeproj"
