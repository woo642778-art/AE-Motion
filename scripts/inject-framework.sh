#!/bin/bash
set -euo pipefail
if [[ $# -ne 3 ]]; then echo "usage: $0 input.ipa AEMotionExtensionsHost.framework output.ipa" >&2; exit 2; fi
command -v insert_dylib >/dev/null || { echo "insert_dylib is required on macOS" >&2; exit 1; }
INPUT="$1"; FRAMEWORK="$2"; OUTPUT="$3"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
unzip -q "$INPUT" -d "$TMP"
APP="$(find "$TMP/Payload" -maxdepth 1 -name '*.app' -type d | head -1)"
EXEC="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Info.plist")"
mkdir -p "$APP/Frameworks"; cp -R "$FRAMEWORK" "$APP/Frameworks/"
insert_dylib --inplace --all-yes '@rpath/AEMotionExtensionsHost.framework/AEMotionExtensionsHost' "$APP/$EXEC"
rm -rf "$APP/_CodeSignature" "$APP/embedded.mobileprovision"
(cd "$TMP" && zip -qry "$OLDPWD/$OUTPUT" Payload)
echo "Created unsigned IPA: $OUTPUT"
