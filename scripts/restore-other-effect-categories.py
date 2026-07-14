#!/usr/bin/env python3
from __future__ import annotations

import argparse
from dataclasses import asdict, dataclass
import html
import json
from pathlib import Path
import re
from xml.etree import ElementTree as ET

PREFERRED_OTHER_EFFECT_IDS = frozenset({
    "com.alightcreative.effects.fillbehind", "com.alightcreative.effects.magnifybg",
    "com.alightcreative.effects.colorgrid", "com.alightcreative.effects.dithh",
    "com.alightcreative.effects.extrudeflat", "com.alightcreative.effects.fuji",
    "com.alightcreative.effects.fireworks", "com.alightcreative.effects.skegradientdisplace",
    "com.alightcreative.effects.linescape", "com.alightcreative.effects.meteor",
    "com.alightcreative.effects.money", "com.alightcreative.effects.mtint",
    "com.alightcreative.effects.newtrails", "com.alightcreative.effects.paperburn",
    "com.alightcreative.effects.partx", "com.alightcreative.effects.simplegrid",
    "com.alightcreative.effects.synthwave", "com.alightcreative.effects.vcr",
    "com.alightcreative.effects.vhsnoise", "com.alightcreative.effects.vortextdust",
    "com.alightcreative.effects.vrcombinednew",
})
EFFECT_RE = re.compile(r"<effect\b(?P<attrs>[^>]*)>", re.IGNORECASE | re.DOTALL)
ATTR_RE = re.compile(r"(?P<name>[A-Za-z_:][\w:.-]*)\s*=\s*(?P<quote>['\"])(?P<value>.*?)(?P=quote)", re.DOTALL)
LARGE_LOOP_RE = re.compile(r"for\s*\([^;]*;\s*[^;]*(?:<=|<)\s*(?:128|192|256|512)(?:\.0)?", re.I)

@dataclass(frozen=True)
class CategoryRepairResult:
    scanned: int
    preferredMatched: int
    autoSelected: int
    changed: int
    otherCount: int
    selectedEffectIDs: list[str]


def resolve_effects_directory(target: Path) -> Path:
    if target.name == "BuiltinEffects": return target
    candidate = target / "BuiltinEffects"
    if candidate.is_dir(): return candidate
    raise FileNotFoundError(f"BuiltinEffects directory not found under: {target}")


def attributes(tag: str) -> dict[str, str]:
    return {m.group("name").lower(): html.unescape(m.group("value")) for m in ATTR_RE.finditer(tag)}


def replace_attribute(tag: str, name: str, value: str) -> str:
    escaped = html.escape(value, quote=True)
    pattern = re.compile(rf"(?P<prefix>\b{re.escape(name)}\s*=\s*)(?P<quote>['\"])(?P<value>.*?)(?P=quote)", re.IGNORECASE | re.DOTALL)
    if pattern.search(tag):
        return pattern.sub(lambda m: f"{m.group('prefix')}{m.group('quote')}{escaped}{m.group('quote')}", tag, count=1)
    return tag[:-1].rstrip() + f' {name}="{escaped}">' 


def load_allowed_records(report_path: Path | None) -> dict[str, dict[str, object]]:
    if report_path is None: return {}
    report = json.loads(report_path.read_text(encoding="utf-8"))
    return {record.get("effectID", "").lower(): record for record in report.get("records", [])}


def runtime_safe_candidate(path: Path, opening_attrs: dict[str, str], record: dict[str, object] | None) -> bool:
    if opening_attrs.get("category", "").strip().lower() not in {"procedural", "other"}: return False
    effect_id = opening_attrs.get("id", "").strip().lower()
    if not effect_id or re.fullmatch(r"[0-9a-f]{32,}", effect_id): return False
    if effect_id.startswith("com.alightcreative.blend.") or effect_id.startswith("com.alightcreative.internal."): return False
    if opening_attrs.get("deprecated", "false").lower() == "true": return False
    if opening_attrs.get("experimental", "false").lower() == "true": return False
    if record is not None:
        if record.get("status") not in {"existingWorking", "implementedUnverified", "implementedVerified"}: return False
        if record.get("dependencies") or record.get("resources"): return False
        if any(finding.get("severity") == "error" for finding in record.get("findings", [])): return False
    text = path.read_text(encoding="utf-8")
    if "<shader" not in text.lower() and "<script" not in text.lower(): return False
    if LARGE_LOOP_RE.search(text): return False
    try: root = ET.fromstring(text)
    except ET.ParseError: return False
    buffers = [element for element in root.iter("texture") if element.attrib.get("srcType", "").lower() == "buffer"]
    passes = list(root.iter("pass"))
    return not buffers and len(passes) <= 1


def restore_other_categories(target: Path, report_path: Path | None = None, target_count: int = 64, manifest_path: Path | None = None) -> CategoryRepairResult:
    effects = resolve_effects_directory(target)
    records = load_allowed_records(report_path)
    descriptors: list[tuple[Path, str, dict[str, str]]] = []
    scanned = 0
    for path in sorted(effects.glob("*.xml")):
        original = path.read_text(encoding="utf-8")
        match = EFFECT_RE.search(original)
        if not match: continue
        scanned += 1
        descriptors.append((path, match.group(0), attributes(match.group(0))))

    preferred: list[tuple[Path, str, dict[str, str]]] = []
    automatic: list[tuple[Path, str, dict[str, str]]] = []
    for item in descriptors:
        path, _, descriptor_attrs = item
        effect_id = descriptor_attrs.get("id", "").strip().lower()
        if effect_id in PREFERRED_OTHER_EFFECT_IDS and runtime_safe_candidate(path, descriptor_attrs, records.get(effect_id)):
            preferred.append(item)
        elif runtime_safe_candidate(path, descriptor_attrs, records.get(effect_id)):
            automatic.append(item)

    automatic.sort(key=lambda item: (item[2].get("name", "").lower(), item[2].get("id", "").lower(), item[0].name.lower()))
    selected = preferred + automatic[:max(0, target_count - len(preferred))]
    selected_ids = {item[2].get("id", "").strip().lower() for item in selected}
    changed = 0
    for path, _, descriptor_attrs in descriptors:
        effect_id = descriptor_attrs.get("id", "").strip().lower()
        if effect_id not in selected_ids: continue
        original = path.read_text(encoding="utf-8")
        match = EFFECT_RE.search(original)
        if not match: continue
        updated = replace_attribute(match.group(0), "category", "other")
        tags = [value.strip() for value in re.split(r"[,;]", descriptor_attrs.get("tags", "")) if value.strip()]
        lowered = {value.lower() for value in tags}
        for value in ("other", "imported"):
            if value not in lowered: tags.append(value); lowered.add(value)
        updated = replace_attribute(updated, "tags", ",".join(tags))
        if updated != match.group(0):
            path.write_text(original[:match.start()] + updated + original[match.end():], encoding="utf-8")
            changed += 1

    final_ids: list[str] = []
    for path in sorted(effects.glob("*.xml")):
        match = EFFECT_RE.search(path.read_text(encoding="utf-8"))
        if not match: continue
        descriptor_attrs = attributes(match.group(0))
        if descriptor_attrs.get("category", "").strip().lower() == "other": final_ids.append(descriptor_attrs.get("id", ""))

    result = CategoryRepairResult(scanned, len(preferred), max(0, len(selected) - len(preferred)), changed, len(final_ids), sorted(final_ids))
    if manifest_path is not None:
        manifest_path.parent.mkdir(parents=True, exist_ok=True)
        manifest_path.write_text(json.dumps({"schemaVersion": 2, **asdict(result)}, indent=2) + "\n", encoding="utf-8")
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("target", type=Path)
    parser.add_argument("--report", type=Path)
    parser.add_argument("--target-count", type=int, default=64)
    parser.add_argument("--manifest", type=Path)
    parser.add_argument("--require-populated-other", action="store_true")
    args = parser.parse_args()
    result = restore_other_categories(args.target.expanduser().resolve(), args.report.expanduser().resolve() if args.report else None, max(args.target_count, 1), args.manifest.expanduser().resolve() if args.manifest else None)
    print(f"Scanned {result.scanned}; preferred {result.preferredMatched}; auto {result.autoSelected}; changed {result.changed}; Other category {result.otherCount}")
    if args.require_populated_other and result.otherCount == 0:
        print("Other category integrity failure: no safe descriptors are assigned to category='other'.", file=__import__('sys').stderr)
        return 2
    if result.otherCount < args.target_count:
        print(f"Other category warning: requested {args.target_count}, selected {result.otherCount} safe descriptors.")
    return 0

if __name__ == "__main__": raise SystemExit(main())
