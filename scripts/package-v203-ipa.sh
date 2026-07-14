#!/bin/bash
set -euo pipefail

if [[ $# -lt 3 || $# -gt 4 ]]; then
  echo "Usage: $0 <base.ipa> <AEMotionExtensionsHost.framework> <output.ipa> [icon.png]" >&2
  exit 64
fi
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASE="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
FRAMEWORK="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
OUTPUT="$(cd "$(dirname "$3")" && pwd)/$(basename "$3")"
ICON="${4:-}"
[[ -f "$BASE" ]] || { echo "Base IPA not found" >&2; exit 66; }
[[ -f "$FRAMEWORK/AEMotionExtensionsHost" ]] || { echo "Framework executable missing" >&2; exit 66; }
[[ -z "$ICON" || -f "$ICON" ]] || { echo "Icon source missing" >&2; exit 66; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/aemotion-v203.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
unzip -q "$BASE" -d "$WORK/root"
APP="$(find "$WORK/root/Payload" -maxdepth 2 -type d -name '*.app' -print -quit)"
[[ -n "$APP" ]] || { echo "App bundle missing" >&2; exit 65; }
EXEC_NAME="$(python3 - "$APP/Info.plist" <<'PY'
import plistlib,sys
with open(sys.argv[1],'rb') as f: print(plistlib.load(f)['CFBundleExecutable'])
PY
)"
EXEC="$APP/$EXEC_NAME"
MAIN_SHA="$(shasum -a 256 "$EXEC" | awk '{print $1}')"
FRAMEWORK_SHA="$(shasum -a 256 "$FRAMEWORK/AEMotionExtensionsHost" | awk '{print $1}')"

mkdir -p "$APP/Frameworks"
rm -rf "$APP/Frameworks/AEMotionExtensionsHost.framework"
cp -a "$FRAMEWORK" "$APP/Frameworks/AEMotionExtensionsHost.framework"
python3 "$ROOT/scripts/normalize-effect-search-metadata.py" --require-native-groups "$APP"
REPORT="$WORK/effect-integrity.json"
set +e
PYTHONPATH="$ROOT/scripts" python3 "$ROOT/scripts/audit-builtin-effects.py" "$APP" --output "$REPORT"
AUDIT_STATUS=$?
set -e
[[ $AUDIT_STATUS -eq 0 || $AUDIT_STATUS -eq 2 || $AUDIT_STATUS -eq 3 ]] || exit "$AUDIT_STATUS"
PYTHONPATH="$ROOT/scripts" python3 "$ROOT/scripts/quarantine-builtin-effects.py" "$APP" --report "$REPORT" --mode apply
FINAL="$WORK/final-effect-integrity.json"
PYTHONPATH="$ROOT/scripts" python3 "$ROOT/scripts/audit-builtin-effects.py" "$APP" --output "$FINAL"
python3 - "$FINAL" <<'PY'
import json,sys
r=json.load(open(sys.argv[1],encoding='utf-8'))
bad=[x for x in r['records'] if x['status'] not in {'existingWorking','implementedUnverified','implementedVerified'}]
if bad: raise SystemExit('Unsafe effects remain after quarantine')
PY
cp "$FINAL" "$APP/AEMotionDiagnostics/final-effect-integrity.json"
if [[ -n "$ICON" ]]; then python3 "$ROOT/scripts/apply-app-branding.py" "$APP" "$ICON"; fi
[[ "$(shasum -a 256 "$EXEC" | awk '{print $1}')" == "$MAIN_SHA" ]] || { echo "Main executable changed" >&2; exit 70; }
find "$APP" -type d -name _CodeSignature -prune -exec rm -rf {} +
find "$APP" -type f \( -name embedded.mobileprovision -o -name CodeResources \) -delete
python3 - "$APP/Info.plist" "$APP/AEMotionDiagnostics/package-manifest.json" "$MAIN_SHA" "$FRAMEWORK_SHA" <<'PY'
import json,plistlib,sys
with open(sys.argv[1],'rb') as f: p=plistlib.load(f)
m={'schemaVersion':1,'release':'v2.0.3a-beta16','displayName':p.get('CFBundleDisplayName'),'bundleIdentifier':p.get('CFBundleIdentifier'),'mainExecutableSHA256':sys.argv[3],'frameworkExecutableSHA256':sys.argv[4]}
open(sys.argv[2],'w',encoding='utf-8').write(json.dumps(m,indent=2)+'\n')
PY
rm -f "$OUTPUT"
(cd "$WORK/root" && zip -qry "$OUTPUT" Payload)
unzip -tq "$OUTPUT" >/dev/null
if unzip -Z1 "$OUTPUT" | grep -Eq '(^|/)(_CodeSignature|embedded\.mobileprovision)(/|$)'; then
  echo "Signature material remains" >&2; exit 70
fi
echo "Created $OUTPUT"
echo "IPA SHA-256: $(shasum -a 256 "$OUTPUT" | awk '{print $1}')"
echo "Main executable SHA-256: $MAIN_SHA"
echo "Framework executable SHA-256: $FRAMEWORK_SHA"
