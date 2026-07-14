#!/bin/bash
set -euo pipefail

if [[ $# -lt 3 || $# -gt 4 ]]; then
  echo "Usage: $0 <v2.0.3a-beta16.ipa> <AEMotionExtensionsHost.framework> <output.ipa> [icon.png]" >&2
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

WORK="$(mktemp -d "${TMPDIR:-/tmp}/aemotion-v21.XXXXXX")"
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
python3 "$ROOT/scripts/restore-other-effect-categories.py" --require-populated-other "$APP"

REPORT="$WORK/effect-integrity.json"
set +e
PYTHONPATH="$ROOT/scripts" python3 "$ROOT/scripts/audit-builtin-effects.py" "$APP" --output "$REPORT"
AUDIT_STATUS=$?
set -e
[[ $AUDIT_STATUS -eq 0 || $AUDIT_STATUS -eq 2 || $AUDIT_STATUS -eq 3 ]] || exit "$AUDIT_STATUS"
FINAL="$WORK/final-effect-integrity.json"
cp "$REPORT" "$FINAL"
python3 - "$FINAL" "$APP" <<'PY'
import json,re,sys
from pathlib import Path
report=json.load(open(sys.argv[1],encoding='utf-8'))
bad=[x for x in report['records'] if x['status'] not in {'existingWorking','implementedUnverified','implementedVerified'}]
if bad: raise SystemExit('Unsafe effects remain after quarantine')
app=Path(sys.argv[2]); other=0
for path in (app/'BuiltinEffects').glob('*.xml'):
    text=path.read_text(encoding='utf-8')
    match=re.search(r'<effect\b([^>]*)>',text,re.I|re.S)
    if match and re.search(r'\bcategory\s*=\s*["\']other["\']',match.group(0),re.I): other+=1
if other == 0: raise SystemExit('Other category is empty after packaging')
print(f'Other category descriptors: {other}')
PY
mkdir -p "$APP/AEMotionDiagnostics"
cp "$FINAL" "$APP/AEMotionDiagnostics/final-effect-integrity.json"
cat > "$APP/AEMotionDiagnostics/project-reliability-capabilities.json" <<'JSON'
{
  "schemaVersion": 1,
  "release": "v2.1-beta17",
  "projectSchema": 1,
  "features": [
    "atomic-project-store",
    "write-ahead-journal",
    "crash-recovery",
    "history-snapshots",
    "undo-redo",
    "project-branching",
    "adaptive-proxy-policy",
    "managed-lru-cache",
    "project-doctor"
  ],
  "privateHostProjectDatabaseAccess": false
}
JSON
if [[ -n "$ICON" ]]; then python3 "$ROOT/scripts/apply-app-branding.py" "$APP" "$ICON"; fi
[[ "$(shasum -a 256 "$EXEC" | awk '{print $1}')" == "$MAIN_SHA" ]] || { echo "Main executable changed" >&2; exit 70; }
find "$APP" -type d -name _CodeSignature -prune -exec rm -rf {} +
find "$APP" -type f \( -name embedded.mobileprovision -o -name CodeResources \) -delete
python3 - "$APP/Info.plist" "$APP/AEMotionDiagnostics/package-manifest.json" "$MAIN_SHA" "$FRAMEWORK_SHA" "$APP" <<'PY'
import json,plistlib,re,sys
from pathlib import Path
with open(sys.argv[1],'rb') as f: p=plistlib.load(f)
app=Path(sys.argv[5]); counts={}
for path in (app/'BuiltinEffects').glob('*.xml'):
    text=path.read_text(encoding='utf-8')
    match=re.search(r'<effect\b([^>]*)>',text,re.I|re.S)
    if not match: continue
    category_match=re.search(r'\bcategory\s*=\s*(["\'])(.*?)\1',match.group(0),re.I|re.S)
    category=(category_match.group(2).strip().lower() if category_match else '')
    counts[category]=counts.get(category,0)+1
manifest={
  'schemaVersion':1,
  'release':'v2.1-beta17',
  'displayName':p.get('CFBundleDisplayName'),
  'bundleIdentifier':p.get('CFBundleIdentifier'),
  'mainExecutableSHA256':sys.argv[3],
  'frameworkExecutableSHA256':sys.argv[4],
  'projectSchemaVersion':1,
  'effectCategoryCounts':dict(sorted(counts.items())),
}
open(sys.argv[2],'w',encoding='utf-8').write(json.dumps(manifest,indent=2)+'\n')
PY
rm -f "$OUTPUT"
(cd "$WORK/root" && zip -qry "$OUTPUT" Payload)
unzip -tq "$OUTPUT" >/dev/null
if unzip -Z1 "$OUTPUT" | grep -Eq '(^|/)(_CodeSignature|embedded\.mobileprovision)(/|$)'; then
  echo "Signature material remains" >&2; exit 70
fi
python3 - "$OUTPUT" <<'PY'
import plistlib,sys,zipfile
with zipfile.ZipFile(sys.argv[1]) as z:
    info=next(x for x in z.namelist() if x.startswith('Payload/') and x.endswith('.app/Info.plist'))
    p=plistlib.loads(z.read(info))
    assert p.get('CFBundleDisplayName') == 'AE motion'
    assert p.get('CFBundleIdentifier') == 'com.alightcreative.motion'
PY
echo "Created $OUTPUT"
echo "IPA SHA-256: $(shasum -a 256 "$OUTPUT" | awk '{print $1}')"
echo "Main executable SHA-256: $MAIN_SHA"
echo "Framework executable SHA-256: $FRAMEWORK_SHA"
