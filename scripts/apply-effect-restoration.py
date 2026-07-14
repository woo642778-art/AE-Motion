#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import shutil
from dataclasses import asdict, dataclass
from pathlib import Path, PurePosixPath
from xml.etree import ElementTree as ET


@dataclass(frozen=True)
class AppliedRepair:
    effectID: str
    fileName: str
    baselineDescriptorSHA256: str
    repairDescriptorSHA256: str
    originalCategory: str
    copiedResources: list[str]


@dataclass(frozen=True)
class RestorationResult:
    schemaVersion: int
    appliedIDs: list[str]
    records: list[AppliedRepair]


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _records_by_id(payload: dict[str, object]) -> dict[str, dict[str, object]]:
    records = payload.get("records", [])
    return {str(record["effectID"]).lower(): record for record in records}


def _safe_relative(value: str) -> PurePosixPath:
    relative = PurePosixPath(value)
    if relative.is_absolute() or ".." in relative.parts:
        raise ValueError(f"unsafe resource path: {value}")
    return relative


def _declared_resources(root: ET.Element) -> list[str]:
    resource_attrs = {"src", "resource", "file", "path", "lut", "font", "asset"}
    values: set[str] = set()
    for element in root.iter():
        for key, value in element.attrib.items():
            candidate = value.strip()
            if key.lower() in resource_attrs and candidate and not candidate.startswith(("#", "content", "buffer")):
                values.add(candidate)
    thumb = root.attrib.get("thumb", "").strip()
    if thumb:
        values.add(thumb)
    return sorted(values)


def _copy_resource(app_effects: Path, repair_root: Path, effect_id: str, resource: str) -> bool:
    relative = _safe_relative(resource)
    destination = app_effects.joinpath(*relative.parts)
    candidates = [
        repair_root.joinpath(*relative.parts),
        repair_root / "resources" / effect_id / Path(*relative.parts),
    ]
    source = next((candidate for candidate in candidates if candidate.is_file()), None)
    if source is None:
        if destination.is_file():
            return False
        raise FileNotFoundError(f"repair resource missing for {effect_id}: {resource}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)
    return True


def apply_repairs(
    app: Path,
    baseline: dict[str, object],
    queue: dict[str, object],
    repair_root: Path,
) -> RestorationResult:
    app = Path(app).resolve()
    repair_root = Path(repair_root).resolve()
    effects = app / "BuiltinEffects"
    effects.mkdir(parents=True, exist_ok=True)
    baseline_by_id = _records_by_id(baseline)
    applied: list[AppliedRepair] = []

    for queue_record in sorted(queue.get("records", []), key=lambda item: str(item["effectID"]).lower()):
        effect_id = str(queue_record["effectID"])
        key = effect_id.lower()
        baseline_record = baseline_by_id.get(key)
        if baseline_record is None:
            raise KeyError(f"baseline record missing for {effect_id}")
        file_name = str(queue_record["fileName"])
        repair_descriptor = repair_root / file_name
        if not repair_descriptor.is_file():
            raise FileNotFoundError(f"repair descriptor missing for {effect_id}: {repair_descriptor}")
        try:
            root = ET.fromstring(repair_descriptor.read_text(encoding="utf-8"))
        except ET.ParseError as error:
            raise ValueError(f"repair descriptor XML invalid for {effect_id}: {error}") from error
        repaired_id = root.attrib.get("id", "").strip()
        if repaired_id.lower() != key:
            raise ValueError(f"effect ID changed for {effect_id}: {repaired_id}")
        expected_category = str(baseline_record["originalCategory"]).strip().lower()
        repaired_category = root.attrib.get("category", "").strip().lower()
        if repaired_category != expected_category:
            raise ValueError(
                f"category mismatch for {effect_id}: expected {expected_category}, found {repaired_category}"
            )
        copied: list[str] = []
        for resource in _declared_resources(root):
            if _copy_resource(effects, repair_root, effect_id, resource):
                copied.append(resource)
        destination = effects / file_name
        shutil.copy2(repair_descriptor, destination)
        copied.sort()
        applied.append(
            AppliedRepair(
                effectID=effect_id,
                fileName=file_name,
                baselineDescriptorSHA256=str(queue_record["baselineDescriptorSHA256"]),
                repairDescriptorSHA256=sha256(destination),
                originalCategory=expected_category,
                copiedResources=copied,
            )
        )

    return RestorationResult(
        schemaVersion=1,
        appliedIDs=[record.effectID for record in applied],
        records=applied,
    )


def main() -> int:
    parser = argparse.ArgumentParser(description="Apply the immutable Beta 20 effect repair set.")
    parser.add_argument("app", type=Path)
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--queue", type=Path, required=True)
    parser.add_argument("--repair-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = apply_repairs(
        args.app,
        json.loads(args.baseline.read_text(encoding="utf-8")),
        json.loads(args.queue.read_text(encoding="utf-8")),
        args.repair_root,
    )
    payload = {
        "schemaVersion": result.schemaVersion,
        "appliedCount": len(result.appliedIDs),
        "appliedIDs": result.appliedIDs,
        "records": [asdict(record) for record in result.records],
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"Applied repairs: {len(result.appliedIDs)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
