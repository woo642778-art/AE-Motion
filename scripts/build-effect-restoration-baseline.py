#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import tempfile
import zipfile
from dataclasses import asdict, dataclass
from pathlib import Path, PurePosixPath
from xml.etree import ElementTree as ET


@dataclass(frozen=True)
class BaselineEffectRecord:
    effectID: str
    fileName: str
    originalCategory: str
    displayName: str
    descriptorSHA256: str
    shaderSHA256: str | None
    scriptSHA256: str | None
    parameters: list[dict[str, str]]
    textures: list[dict[str, str]]
    passes: list[dict[str, str]]
    resources: list[str]
    thumbnail: str | None
    sourceLocation: str
    quarantineReason: str | None


@dataclass(frozen=True)
class BaselineManifest:
    schemaVersion: int
    sourceIPASHA256: str
    records: dict[str, BaselineEffectRecord]


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _body_hash(elements: list[ET.Element]) -> str | None:
    bodies = [(element.text or "").strip() for element in elements]
    bodies = [body for body in bodies if body]
    if not bodies:
        return None
    return _sha256("\n\n".join(bodies).encode("utf-8"))


def _declared_resources(root: ET.Element) -> list[str]:
    resource_attrs = {"src", "resource", "file", "path", "lut", "font", "asset"}
    values: set[str] = set()
    for element in root.iter():
        for key, value in element.attrib.items():
            normalized = key.lower()
            candidate = value.strip()
            if not candidate:
                continue
            if normalized in resource_attrs and not candidate.startswith(("content", "buffer", "#")):
                values.add(candidate)
    thumb = root.attrib.get("thumb", "").strip()
    if thumb:
        values.add(thumb)
    return sorted(values)


def _parse_record(data: bytes, archive_path: str) -> BaselineEffectRecord:
    try:
        root = ET.fromstring(data.decode("utf-8"))
    except (UnicodeDecodeError, ET.ParseError) as error:
        raise ValueError(f"invalid baseline descriptor {archive_path}: {error}") from error
    if root.tag.lower() != "effect":
        raise ValueError(f"invalid baseline descriptor root: {archive_path}")
    effect_id = root.attrib.get("id", "").strip()
    if not effect_id:
        raise ValueError(f"baseline descriptor has no effect ID: {archive_path}")
    category = root.attrib.get("category", "").strip().lower()
    if not category:
        raise ValueError(f"baseline descriptor has no category: {archive_path}")
    parameter_tags = {"slider", "spinner", "integer", "switch", "selector", "color", "point", "angle", "text", "curve"}
    parameters = [dict(sorted(element.attrib.items())) | {"type": element.tag.lower()} for element in root.iter() if element.tag.lower() in parameter_tags]
    textures = [dict(sorted(element.attrib.items())) for element in root.iter() if element.tag.lower() == "texture"]
    passes = [dict(sorted(element.attrib.items())) for element in root.iter() if element.tag.lower() == "pass"]
    is_quarantine = "/AEMotionQuarantine/" in archive_path
    return BaselineEffectRecord(
        effectID=effect_id,
        fileName=PurePosixPath(archive_path).name,
        originalCategory=category,
        displayName=root.attrib.get("name", effect_id).strip() or effect_id,
        descriptorSHA256=_sha256(data),
        shaderSHA256=_body_hash([element for element in root.iter() if element.tag.lower() == "shader"]),
        scriptSHA256=_body_hash([element for element in root.iter() if element.tag.lower() == "script"]),
        parameters=parameters,
        textures=textures,
        passes=passes,
        resources=_declared_resources(root),
        thumbnail=root.attrib.get("thumb", "").strip() or None,
        sourceLocation=archive_path,
        quarantineReason="previous_release_quarantine" if is_quarantine else None,
    )


def _is_descriptor_path(name: str) -> bool:
    if not name.endswith(".xml"):
        return False
    parts = PurePosixPath(name).parts
    try:
        app_index = next(i for i, part in enumerate(parts) if part.endswith(".app"))
    except StopIteration:
        return False
    tail = parts[app_index + 1 :]
    return (
        len(tail) >= 2 and tail[0] == "BuiltinEffects"
    ) or (
        len(tail) >= 3 and tail[0] == "AEMotionQuarantine" and "BuiltinEffects" in tail
    )


def build_baseline(ipa_path: Path) -> BaselineManifest:
    ipa_path = Path(ipa_path).resolve()
    if not ipa_path.is_file():
        raise FileNotFoundError(ipa_path)
    records: dict[str, BaselineEffectRecord] = {}
    with zipfile.ZipFile(ipa_path) as archive:
        names = sorted(name for name in archive.namelist() if _is_descriptor_path(name))
        for name in names:
            record = _parse_record(archive.read(name), name)
            key = record.effectID.lower()
            existing = records.get(key)
            if existing is None:
                records[key] = record
                continue
            if existing.descriptorSHA256 != record.descriptorSHA256:
                raise ValueError(
                    f"conflicting baseline descriptor for {record.effectID}: "
                    f"{existing.sourceLocation} vs {record.sourceLocation}"
                )
            if "/AEMotionQuarantine/" in existing.sourceLocation and "/AEMotionQuarantine/" not in record.sourceLocation:
                records[key] = record
    return BaselineManifest(schemaVersion=1, sourceIPASHA256=_sha256(ipa_path.read_bytes()), records=records)


def manifest_to_json(manifest: BaselineManifest) -> dict[str, object]:
    records = [asdict(manifest.records[key]) for key in sorted(manifest.records)]
    return {
        "schemaVersion": manifest.schemaVersion,
        "sourceIPASHA256": manifest.sourceIPASHA256,
        "effectCount": len(records),
        "records": records,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Build the canonical AE motion effect-restoration baseline.")
    parser.add_argument("ipa", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--require-count", type=int, default=700)
    args = parser.parse_args()
    manifest = build_baseline(args.ipa)
    payload = manifest_to_json(manifest)
    if payload["effectCount"] != args.require_count:
        raise SystemExit(f"Baseline count mismatch: expected {args.require_count}, found {payload['effectCount']}")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"Baseline effects: {payload['effectCount']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
