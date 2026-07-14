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

[[ -f "$BASE" ]] || { echo "Beta 17 base IPA not found" >&2; exit 66; }
[[ -f "$FRAMEWORK/AEMotionExtensionsHost" ]] || { echo "Framework executable missing" >&2; exit 66; }
[[ -z "$ICON" || -f "$ICON" ]] || { echo "Icon source missing" >&2; exit 66; }
[[ -f "$ROOT/Effects/v2.2/bccedgeglow.xml" ]] || { echo "BCC Edge Glow repair descriptor missing" >&2; exit 66; }
[[ -f "$ROOT/Effects/v2.2/blackbars.xml" ]] || { echo "Black Bars repair descriptor missing" >&2; exit 66; }
[[ -f "$ROOT/Effects/v2.2/device-qualification.json" ]] || { echo "Device qualification manifest missing" >&2; exit 66; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/aemotion-v22-beta19.XXXXXX")"
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
python3 "$ROOT/scripts/effect-runtime-stability.py" "$APP" \
  --repairs "$ROOT/Effects/v2.2" \
  --manifest "$APP/AEMotionDiagnostics/runtime-effect-stability.json"

python3 - "$APP/BuiltinEffects/thumb/bccedgeglow.png" <<'PY'
from pathlib import Path
import math,struct,sys,zlib
path=Path(sys.argv[1]); path.parent.mkdir(parents=True,exist_ok=True)
w,h=256,256
rows=[]
for y in range(h):
    row=bytearray([0])
    for x in range(w):
        nx=(x-w/2)/(w/2); ny=(y-h/2)/(h/2)
        radius=math.hypot(nx,ny)
        edge=math.exp(-((abs(radius-0.52)/0.07)**2))
        glow=math.exp(-((abs(radius-0.52)/0.22)**2))*0.8
        grid=0.12 if ((x//24)+(y//24))%2==0 else 0.04
        r=int(min(255,7+45*glow+100*edge+30*grid))
        g=int(min(255,12+130*glow+120*edge+25*grid))
        b=int(min(255,24+230*glow+220*edge+35*grid))
        row.extend((r,g,b,255))
    rows.append(bytes(row))
def chunk(kind,data):
    return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data)&0xffffffff)
png=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',w,h,8,6,0,0,0))+chunk(b'IDAT',zlib.compress(b''.join(rows),9))+chunk(b'IEND',b'')
path.write_bytes(png)
PY

python3 "$ROOT/scripts/validate-effect-thumbnails.py" "$APP" \
  --require-effect-id com.alightcreative.effects.bccedgeglow \
  --require-effect-id com.alightcreative.effects.bbmaker \
  --output "$APP/AEMotionDiagnostics/effect-thumbnails.json"

INITIAL_REPORT="$APP/AEMotionDiagnostics/initial-effect-integrity.json"
set +e
PYTHONPATH="$ROOT/scripts" python3 "$ROOT/scripts/audit-builtin-effects.py" "$APP" --output "$INITIAL_REPORT"
AUDIT_STATUS=$?
set -e
[[ $AUDIT_STATUS -eq 0 || $AUDIT_STATUS -eq 2 || $AUDIT_STATUS -eq 3 ]] || exit "$AUDIT_STATUS"

CI_REPORT="$APP/AEMotionDiagnostics/ci-visual-qualification.json"
python3 "$ROOT/scripts/effect-visual-qualification.py" "$APP" \
  --integrity-report "$INITIAL_REPORT" \
  --output "$CI_REPORT"

FINAL_REPORT="$APP/AEMotionDiagnostics/final-effect-integrity.json"
set +e
PYTHONPATH="$ROOT/scripts" python3 "$ROOT/scripts/audit-builtin-effects.py" "$APP" --output "$FINAL_REPORT"
FINAL_STATUS=$?
set -e
[[ $FINAL_STATUS -eq 0 || $FINAL_STATUS -eq 2 || $FINAL_STATUS -eq 3 ]] || exit "$FINAL_STATUS"

OTHER_REPORT="$APP/AEMotionDiagnostics/other-category-selection.json"
python3 "$ROOT/scripts/restore-other-effect-categories.py" "$APP" \
  --integrity-report "$FINAL_REPORT" \
  --ci-report "$CI_REPORT" \
  --device-report "$ROOT/Effects/v2.2/device-qualification.json" \
  --manifest "$OTHER_REPORT"

cat > "$APP/AEMotionDiagnostics/contextual-editing-capabilities.json" <<'JSON'
{
  "schemaVersion": 1,
  "release": "v2.2-beta19",
  "contextualEditing": ["transform", "graph", "speed", "effect"],
  "livePreview": true,
  "failClosedHostBridge": true,
  "exportReimportRequired": false,
  "privateHostTimelineDatabaseAccess": false
}
JSON

if [[ -n "$ICON" ]]; then
  python3 "$ROOT/scripts/apply-app-branding.py" "$APP" "$ICON"
fi
chmod 755 "$EXEC"

[[ "$(shasum -a 256 "$EXEC" | awk '{print $1}')" == "$MAIN_SHA" ]] || { echo "Main executable changed" >&2; exit 70; }
find "$APP" -type d -name _CodeSignature -prune -exec rm -rf {} +
find "$APP" -type f \( -name embedded.mobileprovision -o -name CodeResources \) -delete

python3 - "$APP" "$MAIN_SHA" "$FRAMEWORK_SHA" <<'PY'
import json,plistlib,re,sys
from pathlib import Path
app=Path(sys.argv[1])
with open(app/'Info.plist','rb') as f: plist=plistlib.load(f)
load=lambda name:json.loads((app/'AEMotionDiagnostics'/name).read_text(encoding='utf-8'))
runtime=load('runtime-effect-stability.json'); visual=load('ci-visual-qualification.json'); thumbnails=load('effect-thumbnails.json'); other=load('other-category-selection.json')
counts={}
for path in (app/'BuiltinEffects').glob('*.xml'):
    text=path.read_text(encoding='utf-8'); match=re.search(r'<effect\b([^>]*)>',text,re.I|re.S)
    if not match: continue
    category_match=re.search(r'\bcategory\s*=\s*(["\'])(.*?)\1',match.group(0),re.I|re.S)
    category=category_match.group(2).strip().lower() if category_match else ''
    counts[category]=counts.get(category,0)+1
package={
  'schemaVersion':2,
  'release':'v2.2-beta19',
  'displayName':plist.get('CFBundleDisplayName'),
  'bundleIdentifier':plist.get('CFBundleIdentifier'),
  'mainExecutableSHA256':sys.argv[2],
  'frameworkExecutableSHA256':sys.argv[3],
  'thumbnailContractValid':bool(thumbnails.get('validForRequiredRepairs')),
  'runtimeEffectsRepaired':runtime.get('repaired',0),
  'runtimeEffectsQuarantined':runtime.get('quarantined',0),
  'visualEffectsQuarantined':visual.get('quarantined',0),
  'otherCategoryCount':other.get('otherCount',0),
  'forcedOtherTargetCount':None,
  'effectCategoryCounts':dict(sorted(counts.items())),
}
assert plist.get('CFBundleDisplayName')=='AE motion'
assert plist.get('CFBundleIdentifier')=='com.alightcreative.motion'
assert package['release']=='v2.2-beta19'
assert package['thumbnailContractValid'] is True
assert package['forcedOtherTargetCount'] is None
(app/'AEMotionDiagnostics/package-manifest.json').write_text(json.dumps(package,indent=2)+'\n',encoding='utf-8')
PY

rm -f "$OUTPUT"
(cd "$WORK/root" && zip -qry "$OUTPUT" Payload)
unzip -tq "$OUTPUT" >/dev/null
if unzip -Z1 "$OUTPUT" | grep -Eq '(^|/)(_CodeSignature|embedded\.mobileprovision|CodeResources)(/|$)'; then
  echo "Signature material remains" >&2
  exit 70
fi

python3 - "$OUTPUT" "$MAIN_SHA" "$FRAMEWORK_SHA" <<'PY'
import json,plistlib,sys,zipfile
with zipfile.ZipFile(sys.argv[1]) as z:
    info=next(x for x in z.namelist() if x.startswith('Payload/') and x.endswith('.app/Info.plist'))
    plist=plistlib.loads(z.read(info))
    assert plist.get('CFBundleDisplayName')=='AE motion'
    assert plist.get('CFBundleIdentifier')=='com.alightcreative.motion'
    package_name=next(x for x in z.namelist() if x.endswith('/AEMotionDiagnostics/package-manifest.json'))
    package=json.loads(z.read(package_name))
    assert package['release']=='v2.2-beta19'
    assert package['mainExecutableSHA256']==sys.argv[2]
    assert package['frameworkExecutableSHA256']==sys.argv[3]
    assert package['thumbnailContractValid'] is True
    assert package['forcedOtherTargetCount'] is None
    edge_name=next(x for x in z.namelist() if x.endswith('/BuiltinEffects/bccedgeglow.xml'))
    assert b'thumb="thumb/bccedgeglow.png"' in z.read(edge_name)
    thumb_name=next(x for x in z.namelist() if x.endswith('/BuiltinEffects/thumb/bccedgeglow.png'))
    assert z.read(thumb_name).startswith(b'\x89PNG\r\n\x1a\n')
    blackbars_name=next(x for x in z.namelist() if x.endswith('/BuiltinEffects/skexnxxbbmaker.xml'))
    assert b'com.alightcreative.effects.bbmaker' in z.read(blackbars_name)
PY

echo "Created $OUTPUT"
echo "IPA SHA-256: $(shasum -a 256 "$OUTPUT" | awk '{print $1}')"
echo "Main executable SHA-256: $MAIN_SHA"
echo "Framework executable SHA-256: $FRAMEWORK_SHA"
