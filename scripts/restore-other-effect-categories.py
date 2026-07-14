#!/usr/bin/env python3
from __future__ import annotations

import argparse
from dataclasses import dataclass
import html
from pathlib import Path
import re

VERIFIED_OTHER_EFFECT_IDS = frozenset({
    "com.alightcreative.effects.fillbehind",
    "com.alightcreative.effects.magnifybg",
    "com.alightcreative.effects.colorgrid",
    "com.alightcreative.effects.dithh",
    "com.alightcreative.effects.extrudeflat",
    "com.alightcreative.effects.fuji",
    "com.alightcreative.effects.fireworks",
    "com.alightcreative.effects.skegradientdisplace",
    "com.alightcreative.effects.linescape",
    "com.alightcreative.effects.meteor",
    "com.alightcreative.effects.money",
    "com.alightcreative.effects.mtint",
    "com.alightcreative.effects.newtrails",
    "com.alightcreative.effects.paperburn",
    "com.alightcreative.effects.partx",
    "com.alightcreative.effects.simplegrid",
    "com.alightcreative.effects.synthwave",
    "com.alightcreative.effects.vcr",
    "com.alightcreative.effects.vhsnoise",
    "com.alightcreative.effects.vortextdust",
    "com.alightcreative.effects.vrcombinednew",
})
EFFECT_RE = re.compile(r"<effect\b(?P<attrs>[^>]*)>", re.IGNORECASE | re.DOTALL)
ATTR_RE = re.compile(r"(?P<name>[A-Za-z_:][\w:.-]*)\s*=\s*(?P<quote>['\"])(?P<value>.*?)(?P=quote)", re.DOTALL)

@dataclass(frozen=True)
class CategoryRepairResult:
    scanned: int
    matched: int
    changed: int
    other_count: int


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
    if pattern.search(tag): return pattern.sub(lambda m: f"{m.group('prefix')}{m.group('quote')}{escaped}{m.group('quote')}", tag, count=1)
    return tag[:-1].rstrip() + f' {name}="{escaped}">' 


def restore_other_categories(target: Path) -> CategoryRepairResult:
    effects = resolve_effects_directory(target)
    scanned = matched = changed = other_count = 0
    for path in sorted(effects.glob("*.xml")):
        original = path.read_text(encoding="utf-8")
        match = EFFECT_RE.search(original)
        if not match: continue
        scanned += 1
        opening = match.group(0); attrs = attributes(opening)
        effect_id = attrs.get("id", "").strip().lower()
        if effect_id in VERIFIED_OTHER_EFFECT_IDS:
            matched += 1
            updated = replace_attribute(opening, "category", "other")
            tags = [x.strip() for x in re.split(r"[,;]", attrs.get("tags", "")) if x.strip()]
            for value in ("other", "imported"):
                if value not in {x.lower() for x in tags}: tags.append(value)
            updated = replace_attribute(updated, "tags", ",".join(tags))
            if updated != opening:
                path.write_text(original[:match.start()] + updated + original[match.end():], encoding="utf-8")
                changed += 1
            other_count += 1
        elif attrs.get("category", "").strip().lower() == "other":
            other_count += 1
    return CategoryRepairResult(scanned, matched, changed, other_count)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("target", type=Path)
    parser.add_argument("--require-populated-other", action="store_true")
    args = parser.parse_args()
    result = restore_other_categories(args.target.expanduser().resolve())
    print(f"Scanned {result.scanned}; matched {result.matched}; changed {result.changed}; Other category {result.other_count}")
    if args.require_populated_other and result.other_count == 0:
        print("Other category integrity failure: no safe descriptors are assigned to category='other'.", file=__import__('sys').stderr)
        return 2
    return 0

if __name__ == "__main__": raise SystemExit(main())
