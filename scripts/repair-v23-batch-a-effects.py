#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import xml.etree.ElementTree as ET
from pathlib import Path

SAFE_HELPERS = r'''
vec2 aeSafeNormalize(vec2 v) { float m = max(length(v), 1.0e-6); return v / m; }
vec3 aeSafeNormalize(vec3 v) { float m = max(length(v), 1.0e-6); return v / m; }
vec4 aeSafeNormalize(vec4 v) { float m = max(length(v), 1.0e-6); return v / m; }
float aeSafeDivisor(float v) { return (v < 0.0 ? -1.0 : 1.0) * max(abs(v), 1.0e-6); }
vec3 aeSafeReciprocal(vec3 v) {
    vec3 s = mix(vec3(-1.0), vec3(1.0), step(vec3(0.0), v));
    return s / max(abs(v), vec3(1.0e-6));
}
'''.strip()

REPLACEMENT_NAMES = (
    "poseshake.xml",
    "sshakeultra.xml",
    "s_dissolveshake.xml",
    "s_shake.xml",
)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def parse_root(path: Path) -> ET.Element:
    return ET.parse(path).getroot()


def is_3d(root: ET.Element) -> bool:
    tags = {part.strip().lower() for part in root.attrib.get("tags", "").split(",")}
    return root.attrib.get("category", "").lower() == "3d" or "3d" in tags


def inject_helpers(text: str) -> tuple[str, bool]:
    if "aeSafeNormalize(" in text:
        return text, False
    if "normalize(" not in text and "1.0/rdd" not in text and "rayDir.z" not in text:
        return text, False
    marker = "<![CDATA["
    if marker in text:
        return text.replace(marker, marker + "\n" + SAFE_HELPERS + "\n", 1), True
    shader_match = re.search(r"(<shader\b[^>]*>)", text)
    if shader_match:
        index = shader_match.end()
        return text[:index] + "\n" + SAFE_HELPERS + "\n" + text[index:], True
    return text, False


def fix_selector_defaults(text: str, root: ET.Element) -> tuple[str, list[str]]:
    changes: list[str] = []
    for selector in root.findall("./params/selector"):
        selector_id = selector.attrib.get("id")
        default = selector.attrib.get("default")
        choices = [choice.attrib.get("value") for choice in selector.findall("./choice")]
        if not selector_id or not choices or default in choices:
            continue
        first = choices[0]
        pattern = re.compile(
            rf'(<selector\b(?=[^>]*\bid="{re.escape(selector_id)}")[^>]*\bdefault=")[^"]+("[^>]*>)'
        )
        text, count = pattern.subn(rf"\g<1>{first}\g<2>", text, count=1)
        if count:
            changes.append(f"selector:{selector_id}:{default}->{first}")
    return text, changes


def patch_dynamic_loops(text: str, root: ET.Element) -> tuple[str, list[str]]:
    changes: list[str] = []
    parameter_ids = {node.attrib.get("id") for node in root.findall("./params/*") if node.attrib.get("id")}

    if "MAX_ITER" in parameter_ids:
        pattern = re.compile(
            r"for\s*\(\s*int\s+(?P<v>[A-Za-z_]\w*)\s*=\s*0\s*;\s*(?P=v)\s*<\s*int\s*\(\s*MAX_ITER\s*\)\s*;\s*(?P=v)\s*\+\+\s*\)\s*\{"
        )
        replacement = (
            "for (int \\g<v> = 0; \\g<v> < 200; \\g<v>++) { "
            "if (\\g<v> >= int(clamp(float(MAX_ITER), 1.0, 200.0))) break;"
        )
        text, count = pattern.subn(replacement, text)
        if count:
            changes.append(f"bounded_MAX_ITER:{count}")

    point_loop = re.compile(
        r"for\s*\(\s*int\s+(?P<v>[A-Za-z_]\w*)\s*=\s*0\s*;\s*(?P=v)\s*<\s*points\s*;\s*(?P=v)\s*\+\+\s*\)\s*\{"
    )
    text, count = point_loop.subn(
        "for (int \\g<v> = 0; \\g<v> < 32; \\g<v>++) { if (\\g<v> >= clamp(points, 1, 32)) break;",
        text,
    )
    if count:
        changes.append(f"bounded_points:{count}")

    furthest_loop = re.compile(
        r"for\s*\(\s*float\s+(?P<v>[A-Za-z_]\w*)\s*=\s*1\.0\s*;\s*(?P=v)\s*<=\s*furthest\s*;\s*(?P=v)\s*\+=\s*1\.0\s*\)\s*\{"
    )
    text, count = furthest_loop.subn(
        r"for (int aePlaneIndex = 1; aePlaneIndex <= 16; aePlaneIndex++) { float \g<v> = float(aePlaneIndex);",
        text,
    )
    if count:
        changes.append(f"bounded_furthest:{count}")

    return text, changes


def patch_known_math(text: str) -> tuple[str, list[str]]:
    changes: list[str] = []

    count = text.count("normalize(")
    if count:
        text = text.replace("normalize(", "aeSafeNormalize(")
        changes.append(f"safe_normalize:{count}")

    patterns = [
        (re.compile(r"1\.0\s*/\s*rdd\b"), "aeSafeReciprocal(rdd)", "safe_reciprocal_rdd"),
        (re.compile(r"1\.\s*/\s*rdd\b"), "aeSafeReciprocal(rdd)", "safe_reciprocal_rdd"),
        (re.compile(r"-rayOrigin\.z\s*/\s*rayDir\.z"), "-rayOrigin.z / aeSafeDivisor(rayDir.z)", "safe_ray_plane_divisor"),
    ]
    for pattern, replacement, label in patterns:
        text, count = pattern.subn(replacement, text)
        if count:
            changes.append(f"{label}:{count}")

    return text, changes


def repair_effects(app_path: Path, repairs_path: Path, report_path: Path | None = None) -> dict:
    effects_path = app_path / "BuiltinEffects"
    if not effects_path.is_dir():
        raise FileNotFoundError(f"BuiltinEffects not found at {effects_path}")

    report: dict = {
        "replacements": [],
        "removed": [],
        "threeDModified": [],
        "threeDScanned": 0,
    }

    for name in REPLACEMENT_NAMES:
        source = repairs_path / name
        destination = effects_path / name
        if not source.is_file():
            raise FileNotFoundError(f"Missing replacement: {source}")
        shutil.copy2(source, destination)
        parse_root(destination)
        report["replacements"].append({
            "file": name,
            "sha256": sha256(destination),
        })

    obsolete = effects_path / "aemotion_s_invert.xml"
    if obsolete.exists():
        obsolete.unlink()
        report["removed"].append("aemotion_s_invert.xml")

    for path in sorted(effects_path.glob("*.xml")):
        try:
            root = parse_root(path)
        except ET.ParseError:
            continue
        if not is_3d(root):
            continue

        report["threeDScanned"] += 1
        original = path.read_text(encoding="utf-8", errors="replace")
        text = original
        transformations: list[str] = []

        if path.name == "clouds3d.xml":
            text, count = re.subn(
                r"\s*<texture\s+id=\"xcipher\"\s+srcType=\"buffer\"\s*/>\s*",
                "\n",
                text,
                count=1,
            )
            if count:
                transformations.append("remove_unwritten_xcipher_buffer")

        text, selector_changes = fix_selector_defaults(text, root)
        transformations.extend(selector_changes)

        text, injected = inject_helpers(text)
        if injected:
            transformations.append("inject_safe_math_helpers")

        text, loop_changes = patch_dynamic_loops(text, root)
        transformations.extend(loop_changes)

        text, math_changes = patch_known_math(text)
        transformations.extend(math_changes)

        if text != original:
            path.write_text(text, encoding="utf-8")
            parse_root(path)
            report["threeDModified"].append({
                "file": path.name,
                "id": root.attrib.get("id", ""),
                "name": root.attrib.get("name", ""),
                "transformations": transformations,
                "sha256": sha256(path),
            })

    if report_path:
        report_path.parent.mkdir(parents=True, exist_ok=True)
        report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return report


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("app_path", type=Path)
    parser.add_argument("--repairs", type=Path, required=True)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    report = repair_effects(args.app_path, args.repairs, args.report)
    print(json.dumps(report, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
