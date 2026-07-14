#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path, PurePosixPath
from xml.etree import ElementTree as ET

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


def png_dimensions(path: Path) -> tuple[int, int]:
    data = path.read_bytes()
    if len(data) < 24 or data[:8] != PNG_SIGNATURE or data[12:16] != b"IHDR":
        raise ValueError("invalid_png")
    width = int.from_bytes(data[16:20], "big")
    height = int.from_bytes(data[20:24], "big")
    if width <= 0 or height <= 0:
        raise ValueError("zero_dimension_png")
    return width, height


def exact_case_path(root: Path, relative: PurePosixPath) -> Path | None:
    current = root
    for part in relative.parts:
        if part in {"", "."}:
            continue
        if not current.is_dir():
            return None
        matches = [entry for entry in current.iterdir() if entry.name == part]
        if len(matches) != 1:
            return None
        current = matches[0]
    return current


def validate_thumbnail_contract(app: Path) -> dict[str, object]:
    app = app.resolve()
    effects = app / "BuiltinEffects"
    errors: list[dict[str, str]] = []
    checked: list[dict[str, object]] = []

    for descriptor in sorted(effects.glob("*.xml")):
        try:
            root = ET.fromstring(descriptor.read_text(encoding="utf-8"))
        except (OSError, UnicodeError, ET.ParseError) as error:
            errors.append({"fileName": descriptor.name, "code": "descriptor_parse_failure", "message": str(error)})
            continue
        thumb = root.attrib.get("thumb", "").strip()
        if not thumb:
            continue
        effect_id = root.attrib.get("id", "")
        relative = PurePosixPath(thumb)
        if relative.is_absolute() or ".." in relative.parts:
            errors.append({"effectID": effect_id, "fileName": descriptor.name, "code": "unsafe_thumbnail_path", "path": thumb})
            continue
        asset = exact_case_path(app, relative)
        if asset is None or not asset.is_file():
            errors.append({"effectID": effect_id, "fileName": descriptor.name, "code": "missing_case_sensitive_asset", "path": thumb})
            continue
        try:
            width, height = png_dimensions(asset)
        except ValueError as error:
            errors.append({"effectID": effect_id, "fileName": descriptor.name, "code": str(error), "path": thumb})
            continue
        checked.append({"effectID": effect_id, "fileName": descriptor.name, "path": thumb, "width": width, "height": height})

    return {"schemaVersion": 1, "valid": not errors, "checked": checked, "errors": errors}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("app", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    result = validate_thumbnail_contract(args.app)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2))
    return 0 if result["valid"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
