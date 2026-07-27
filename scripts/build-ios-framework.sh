#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build"
DERIVED="$OUT/DerivedData"
FRAMEWORK="$OUT/AEMotionExtensionsHost.framework"
EXECUTABLE="$FRAMEWORK/AEMotionExtensionsHost"

rm -rf "$OUT"
mkdir -p "$OUT"

xcodebuild \
  -scheme AEMotionExtensionsHost \
  -destination 'generic/platform=iOS' \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  SKIP_INSTALL=NO \
  BUILD_LIBRARY_FOR_DISTRIBUTION=NO \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build

BUILT_FRAMEWORK="$(find "$DERIVED/Build/Products" -name 'AEMotionExtensionsHost.framework' -type d | head -n 1 || true)"
BUILT_DYLIB="$(find "$DERIVED/Build/Products" -name 'libAEMotionExtensionsHost.dylib' -type f | head -n 1 || true)"

if [[ -n "$BUILT_FRAMEWORK" ]]; then
  ditto "$BUILT_FRAMEWORK" "$FRAMEWORK"
elif [[ -n "$BUILT_DYLIB" ]]; then
  mkdir -p "$FRAMEWORK"
  cp "$BUILT_DYLIB" "$EXECUTABLE"
  chmod 755 "$EXECUTABLE"
else
  echo "AEMotionExtensionsHost build product not found" >&2
  exit 1
fi

if [[ ! -f "$EXECUTABLE" ]]; then
  CANDIDATE="$(find "$FRAMEWORK" -maxdepth 1 -type f -perm -111 | head -n 1 || true)"
  if [[ -z "$CANDIDATE" ]]; then
    echo "Framework executable not found" >&2
    exit 1
  fi
  mv "$CANDIDATE" "$EXECUTABLE"
fi

xcrun install_name_tool \
  -id '@rpath/AEMotionExtensionsHost.framework/AEMotionExtensionsHost' \
  "$EXECUTABLE"

python3 - "$FRAMEWORK/Info.plist" <<'PY'
import plistlib
import sys
from pathlib import Path

path = Path(sys.argv[1])
value = {
    "CFBundleDevelopmentRegion": "en",
    "CFBundleExecutable": "AEMotionExtensionsHost",
    "CFBundleIdentifier": "ae-motion-extensions.AEMotionExtensionsHost",
    "CFBundleInfoDictionaryVersion": "6.0",
    "CFBundleName": "AEMotionExtensionsHost",
    "CFBundlePackageType": "FMWK",
    "CFBundleShortVersionString": "2.7.1",
    "CFBundleSupportedPlatforms": ["iPhoneOS"],
    "CFBundleVersion": "839",
    "MinimumOSVersion": "15.0",
    "UIDeviceFamily": [1, 2],
    "UIRequiredDeviceCapabilities": ["arm64"],
}
with path.open("wb") as stream:
    plistlib.dump(value, stream, fmt=plistlib.FMT_XML, sort_keys=True)
PY

file "$EXECUTABLE"
lipo -info "$EXECUTABLE"
otool -D "$EXECUTABLE"

echo "$FRAMEWORK"
