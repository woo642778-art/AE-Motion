#!/usr/bin/env python3
"""Normalize Alight Motion effect XML search metadata without reformatting bodies.

Usage:
    python3 scripts/normalize-effect-search-metadata.py /path/to/AlightMotion.app
    python3 scripts/normalize-effect-search-metadata.py /path/to/BuiltinEffects

The script updates only attributes on the opening <effect> element. It adds
searchable name/id tokens, BCC/BBC/Boris aliases, and maps unsupported custom
categories to categories indexed by the target Alight Motion build.
"""

from __future__ import annotations

import argparse
import html
import re
from pathlib import Path

SUPPORTED = {
    "color", "drawing", "blur", "warp", "procedural", "3d",
    "move", "repeat", "matte", "opacity", "text",
}
CATEGORY_MAP = {
    "lighting": "drawing", "light": "drawing", "glow": "drawing", "edge": "drawing",
    "stylize": "procedural", "style": "procedural", "generator": "procedural", "generate": "procedural",
    "distort": "warp", "distortion": "warp", "transform": "warp", "transition": "warp",
    "colour": "color", "grading": "color", "color grading": "color",
    "mask": "matte", "matte/mask": "matte", "matte-mask": "matte",
}
EFFECT_RE = re.compile(r"<effect\b(?P<attrs>[^>]*)>", re.IGNORECASE | re.DOTALL)
ATTR_RE = re.compile(r"(?P<name>[A-Za-z_:][\w:.-]*)\s*=\s*(?P<quote>['\"])(?P<value>.*?)(?P=quote)", re.DOTALL)
TOKEN_RE = re.compile(r"[A-Za-z0-9]+")


def normalize_category(raw: str | None) -> str:
    value = (raw or "").strip().lower()
    if value in SUPPORTED:
        return value
    return CATEGORY_MAP.get(value, "procedural")


def normalize_tags(name: str, effect_id: str, existing: str | None) -> str:
    ordered: list[str] = []
    seen: set[str] = set()

    def add(raw: str) -> None:
        value = raw.strip().lower()
        if value and value not in seen:
            seen.add(value)
            ordered.append(value)

    for token in re.split(r"[,;]", existing or ""):
        add(token)
    for token in TOKEN_RE.findall(name):
        add(token)
    for token in TOKEN_RE.findall(effect_id):
        if token.lower() not in {"com", "alightcreative", "effects", "effect"}:
            add(token)

    searchable = f"{name} {effect_id} {existing or ''}".lower()
    if "bcc" in searchable or "boris" in searchable:
        for alias in ("bcc", "bbc", "boris", "borisfx", "boris fx", "continuum"):
            add(alias)

    return ",".join(ordered)


def attributes(opening_tag: str) -> dict[str, str]:
    return {
        match.group("name"): html.unescape(match.group("value"))
        for match in ATTR_RE.finditer(opening_tag)
    }


def replace_attribute(opening_tag: str, name: str, value: str) -> str:
    escaped = html.escape(value, quote=True)
    pattern = re.compile(
        rf"(?P<prefix>\b{re.escape(name)}\s*=\s*)(?P<quote>['\"])(?P<value>.*?)(?P=quote)",
        re.IGNORECASE | re.DOTALL,
    )
    if pattern.search(opening_tag):
        return pattern.sub(lambda m: f"{m.group('prefix')}{m.group('quote')}{escaped}{m.group('quote')}", opening_tag, count=1)
    return opening_tag[:-1].rstrip() + f' {name}="{escaped}">' 


def normalize_file(path: Path) -> bool:
    original = path.read_text(encoding="utf-8")
    match = EFFECT_RE.search(original)
    if not match:
        return False

    opening = match.group(0)
    attrs = attributes(opening)
    name = attrs.get("name", path.stem)
    effect_id = attrs.get("id", path.stem)
    category = normalize_category(attrs.get("category"))
    tags = normalize_tags(name, effect_id, attrs.get("tags"))

    updated = replace_attribute(opening, "category", category)
    updated = replace_attribute(updated, "tags", tags)
    if updated == opening:
        return False

    result = original[: match.start()] + updated + original[match.end() :]
    path.write_text(result, encoding="utf-8")
    return True


def resolve_effects_directory(target: Path) -> Path:
    if target.name == "BuiltinEffects":
        return target
    candidate = target / "BuiltinEffects"
    if candidate.is_dir():
        return candidate
    raise FileNotFoundError(f"BuiltinEffects directory not found under: {target}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("target", type=Path, help="AlightMotion.app or BuiltinEffects directory")
    args = parser.parse_args()

    effects = resolve_effects_directory(args.target.expanduser().resolve())
    files = sorted(effects.glob("*.xml"))
    changed = sum(1 for path in files if normalize_file(path))
    print(f"Normalized {changed} of {len(files)} effect XML files in {effects}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
