#!/usr/bin/env python3
from __future__ import annotations

import argparse
from dataclasses import asdict, dataclass
import html
import importlib.util
import json
from pathlib import Path
import re
import sys

EFFECT_RE = re.compile(r"<effect\b(?P<attrs>[^>]*)>", re.IGNORECASE | re.DOTALL)
ATTR_RE = re.compile(r"(?P<name>[A-Za-z_:][\w:.-]*)\s*=\s*(?P<quote>['\"])(?P<value>.*?)(?P=quote)", re.DOTALL)


@dataclass(frozen=True)
class CategoryRepairResult:
    scanned: int
    changed: int
    otherCount: int
    selectedEffectIDs: list[str]
    rejected: list[dict[str, str]]

    @property
    def other_count(self) -> int:
        return self.otherCount


def load_selector():
    path = Path(__file__).with_name("select-qualified-other-effects.py")
    spec = importlib.util.spec_from_file_location("aemotion_other_selector", path)
    if spec is None or spec.loader is None:
        raise RuntimeError("Unable to load Other selector")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def resolve_effects_directory(target: Path) -> Path:
    if target.name == "BuiltinEffects":
        return target
    candidate = target / "BuiltinEffects"
    if candidate.is_dir():
        return candidate
    raise FileNotFoundError(f"BuiltinEffects directory not found under: {target}")


def resolve_app(target: Path) -> Path:
    return target.parent if target.name == "BuiltinEffects" else target


def attributes(tag: str) -> dict[str, str]:
    return {m.group("name").lower(): html.unescape(m.group("value")) for m in ATTR_RE.finditer(tag)}


def replace_attribute(tag: str, name: str, value: str) -> str:
    escaped = html.escape(value, quote=True)
    pattern = re.compile(rf"(?P<prefix>\b{re.escape(name)}\s*=\s*)(?P<quote>['\"])(?P<value>.*?)(?P=quote)", re.IGNORECASE | re.DOTALL)
    if pattern.search(tag):
        return pattern.sub(lambda m: f"{m.group('prefix')}{m.group('quote')}{escaped}{m.group('quote')}", tag, count=1)
    return tag[:-1].rstrip() + f' {name}="{escaped}">'


def normalized_tags(raw: str, selected: bool) -> str:
    tags = [value.strip() for value in re.split(r"[,;]", raw) if value.strip()]
    if selected:
        lowered = {value.lower() for value in tags}
        for value in ("other", "imported"):
            if value not in lowered:
                tags.append(value)
                lowered.add(value)
    else:
        tags = [value for value in tags if value.lower() not in {"other", "imported"}]
    return ",".join(tags)


def restore_other_categories(
    target: Path,
    integrity_report: Path,
    ci_report: Path,
    device_report: Path,
    manifest_path: Path | None = None,
) -> CategoryRepairResult:
    effects = resolve_effects_directory(target)
    app = resolve_app(target)
    selector = load_selector()
    selection = selector.select_qualified_effects(app, integrity_report, ci_report, device_report)
    selected = {effect_id.lower() for effect_id in selection.selectedEffectIDs}
    scanned = 0
    changed = 0

    for path in sorted(effects.glob("*.xml")):
        original = path.read_text(encoding="utf-8")
        match = EFFECT_RE.search(original)
        if not match:
            continue
        scanned += 1
        opening = match.group(0)
        attrs = attributes(opening)
        effect_id = attrs.get("id", "").strip().lower()
        is_selected = effect_id in selected
        category = attrs.get("category", "").strip().lower()
        updated = opening
        if is_selected:
            updated = replace_attribute(updated, "category", "other")
        elif category == "other":
            updated = replace_attribute(updated, "category", "procedural")
        updated = replace_attribute(updated, "tags", normalized_tags(attrs.get("tags", ""), is_selected))
        if updated != opening:
            path.write_text(original[:match.start()] + updated + original[match.end():], encoding="utf-8")
            changed += 1

    final_ids: list[str] = []
    for path in sorted(effects.glob("*.xml")):
        match = EFFECT_RE.search(path.read_text(encoding="utf-8"))
        if not match:
            continue
        attrs = attributes(match.group(0))
        if attrs.get("category", "").strip().lower() == "other":
            final_ids.append(attrs.get("id", ""))

    result = CategoryRepairResult(
        scanned=scanned,
        changed=changed,
        otherCount=len(final_ids),
        selectedEffectIDs=sorted(final_ids),
        rejected=selection.rejected,
    )
    if manifest_path is not None:
        manifest_path.parent.mkdir(parents=True, exist_ok=True)
        manifest_path.write_text(json.dumps({"schemaVersion": 3, **asdict(result)}, indent=2) + "\n", encoding="utf-8")
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("target", type=Path)
    parser.add_argument("--integrity-report", type=Path, required=True)
    parser.add_argument("--ci-report", type=Path, required=True)
    parser.add_argument("--device-report", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    args = parser.parse_args()
    result = restore_other_categories(
        args.target.expanduser().resolve(),
        args.integrity_report.expanduser().resolve(),
        args.ci_report.expanduser().resolve(),
        args.device_report.expanduser().resolve(),
        args.manifest.expanduser().resolve(),
    )
    print(f"Scanned {result.scanned}; changed {result.changed}; Other category {result.otherCount}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
