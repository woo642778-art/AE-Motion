#!/bin/bash
set -euo pipefail

if [[ $# -lt 3 || $# -gt 4 ]]; then
  echo "Usage: $0 <v2.1-beta17.ipa> <AEMotionExtensionsHost.framework> <output.ipa> [icon.png]" >&2
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
[[ -f "$ROOT/Effects/v2.2/bccedgeglow.xml" ]] || { echo "BCC Edge Glow repair descriptor missing" >&2; exit 66; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/aemotion-v22.XXXXXX")"
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

mkdir -p "$APP/Frameworks" "$APP/AEMotionDiagnostics"
rm -rf "$APP/Frameworks/AEMotionExtensionsHost.framework"
cp -a "$FRAMEWORK" "$APP/Frameworks/AEMotionExtensionsHost.framework"

python3 "$ROOT/scripts/normalize-effect-search-metadata.py" --require-native-groups "$APP"
RUNTIME_MANIFEST="$APP/AEMotionDiagnostics/runtime-effect-stability.json"
python3 "$ROOT/scripts/effect-runtime-stability.py" "$APP" --repairs "$ROOT/Effects/v2.2" --manifest "$RUNTIME_MANIFEST"

INITIAL_REPORT="$WORK/initial-effect-integrity.json"
set +e
PYTHONPATH="$ROOT/scripts" python3 "$ROOT/scripts/audit-builtin-effects.py" "$APP" --output "$INITIAL_REPORT"
AUDIT_STATUS=$?
set -e
[[ $AUDIT_STATUS -eq 0 || $AUDIT_STATUS -eq 2 || $AUDIT_STATUS -eq 3 ]] || exit "$AUDIT_STATUS"

OTHER_MANIFEST="$APP/AEMotionDiagnostics/other-category-restoration.json"
python3 "$ROOT/scripts/restore-other-effect-categories.py" "$APP" --report "$INITIAL_REPORT" --target-count 64 --manifest "$OTHER_MANIFEST" --require-populated-other

FINAL_REPORT="$APP/AEMotionDiagnostics/final-effect-integrity.json"
set +e
PYTHONPATH="$ROOT/scripts" python3 "$ROOT/scripts/audit-builtin-effects.py" "$APP" --output "$FINAL_REPORT"
FINAL_AUDIT_STATUS=$?
set -e
[[ $FINAL_AUDIT_STATUS -eq 0 || $FINAL_AUDIT_STATUS -eq 2 || $FINAL_AUDIT_STATUS -eq 3 ]] || exit "$FINAL_AUDIT_STATUS"

python3 - "$FINAL_REPORT" "$RUNTIME_MANIFEST" "$OTHER_MANIFEST" "$APP" "$ROOT/Effects/v2.2/bccedgeglow.xml" <<'PY'
import hashlib,json,re,sys
from pathlib import Path
report=json.load(open(sys.argv[1],encoding='utf-8'))
runtime=json.load(open(sys.argv[2],encoding='utf-8'))
other=json.load(open(sys.argv[3],encoding='utf-8'))
app=Path(sys.argv[4]); repair=Path(sys.argv[5])
bad=[x for x in report['records'] if x['status'] not in {'existingWorking','implementedUnverified','implementedVerified'}]
if bad: raise SystemExit('Unsafe effects remain after runtime quarantine')
if other.get('otherCount',0) < 64: raise SystemExit('Other category restoration did not reach 64 safe effects')
if runtime.get('repaired',0) < 1: raise SystemExit('Known crash effect repair was not applied')
edge=app/'BuiltinEffects'/'bccedgeglow.xml'
if not edge.is_file(): raise SystemExit('BCC Edge Glow is missing after repair')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
if sha(edge)!=sha(repair): raise SystemExit('BCC Edge Glow does not match the clean-room repair descriptor')
text=edge.read_text(encoding='utf-8')
if re.search(r'for\s*\([^;]*;\s*[^;]*(?:<=|<)\s*(?:128|192|256|512)',text,re.I): raise SystemExit('BCC Edge Glow still contains a high-risk loop')
ids=[record.get('effectID','') for record in report['records']]
if len(ids)!=len(set(ids)): raise SystemExit('Duplicate effect IDs remain')
print(f"Effects: {len(ids)}; Other: {other['otherCount']}; runtime quarantined: {runtime['quarantined']}")
PY

cat > "$APP/AEMotionDiagnostics/animation-core-capabilities.json" <<'JSON'
{
  "schemaVersion": 1,
  "release": "v2.2-beta18",
  "features": [
    "unified-keyframe-values", "value-graph", "speed-graph", "bezier-and-procedural-interpolation",
    "gesture-recording", "motion-cleanup", "time-mapping", "professional-velocity",
    "freeze-and-reverse", "bpm-markers", "frame-interpolation-policy", "audio-pitch-policy"
  ],
  "privateHostTimelineDatabaseAccess": false
}
JSON

if [[ -n "$ICON" ]]; then python3 "$ROOT/scripts/apply-app-branding.py" "$APP" "$ICON"; fi
[[ "$(shasum -a 256 "$EXEC" | awk '{print $1}')" == "$MAIN_SHA" ]] || { echo "Main executable changed" >&2; exit 70; }
find "$APP" -type d -name _CodeSignature -prune -exec rm -rf {} +
find "$APP" -type f \( -name embedded.mobileprovision -o -name CodeResources \) -delete

python3 - "$APP/Info.plist" "$APP/AEMotionDiagnostics/package-manifest.json" "$MAIN_SHA" "$FRAMEWORK_SHA" "$APP" "$RUNTIME_MANIFEST" "$OTHER_MANIFEST" <<'PY'
import json,plistlib,re,sys
from pathlib import Path
with open(sys.argv[1],'rb') as f: p=plistlib.load(f)
app=Path(sys.argv[5]); counts={}
for path in (app/'BuiltinEffects').glob('*.xml'):
    text=path.read_text(encoding='utf-8'); match=re.search(r'<effect\b([^>]*)>',text,re.I|re.S)
    if not match: continue
    category_match=re.search(r'\bcategory\s*=\s*(["\'])(.*?)\1',match.group(0),re.I|re.S)
    category=(category_match.group(2).strip().lower() if category_match else '')
    counts[category]=counts.get(category,0)+1
runtime=json.load(open(sys.argv[6],encoding='utf-8')); other=json.load(open(sys.argv[7],encoding='utf-8'))
manifest={'schemaVersion':1,'release':'v2.2-beta18','displayName':p.get('CFBundleDisplayName'),'bundleIdentifier':p.get('CFBundleIdentifier'),'mainExecutableSHA256':sys.argv[3],'frameworkExecutableSHA256':sys.argv[4],'projectSchemaVersion':1,'animationSchemaVersion':1,'effectCategoryCounts':dict(sorted(counts.items())),'runtimeEffectsRepaired':runtime.get('repaired',0),'runtimeEffectsQuarantined':runtime.get('quarantined',0),'otherCategoryCount':other.get('otherCount',0)}
open(sys.argv[2],'w',encoding='utf-8').write(json.dumps(manifest,indent=2)+'\n')
PY

rm -f "$OUTPUT"
(cd "$WORK/root" && zip -qry "$OUTPUT" Payload)
unzip -tq "$OUTPUT" >/dev/null
if unzip -Z1 "$OUTPUT" | grep -Eq '(^|/)(_CodeSignature|embedded\.mobileprovision)(/|$)'; then echo "Signature material remains" >&2; exit 70; fi
python3 - "$OUTPUT" <<'PY'
import json,plistlib,sys,zipfile
with zipfile.ZipFile(sys.argv[1]) as z:
    info=next(x for x in z.namelist() if x.startswith('Payload/') and x.endswith('.app/Info.plist'))
    p=plistlib.loads(z.read(info)); assert p.get('CFBundleDisplayName') == 'AE motion'; assert p.get('CFBundleIdentifier') == 'com.alightcreative.motion'
    package=next(x for x in z.namelist() if x.endswith('/AEMotionDiagnostics/package-manifest.json'))
    manifest=json.loads(z.read(package)); assert manifest['release']=='v2.2-beta18'; assert manifest['otherCategoryCount']>=64; assert manifest['runtimeEffectsRepaired']>=1
PY

echo "Created $OUTPUT"
echo "IPA SHA-256: $(shasum -a 256 "$OUTPUT" | awk '{print $1}')"
echo "Main executable SHA-256: $MAIN_SHA"
echo "Framework executable SHA-256: $FRAMEWORK_SHA"
