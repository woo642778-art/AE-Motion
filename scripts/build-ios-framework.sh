#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build"
rm -rf "$OUT" && mkdir -p "$OUT"
xcodebuild -scheme AEMotionExtensionsHost -destination 'generic/platform=iOS' -configuration Release -derivedDataPath "$OUT/DerivedData" SKIP_INSTALL=NO BUILD_LIBRARY_FOR_DISTRIBUTION=NO build
find "$OUT/DerivedData/Build/Products" -name 'libAEMotionExtensionsHost.dylib' -o -name 'AEMotionExtensionsHost.framework'
