#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
from dataclasses import asdict, dataclass
from pathlib import Path
from xml.etree import ElementTree as ET


@dataclass(frozen=True)
class SelectionResult:
    selectedEffectIDs: list[str]
    otherCount: int
    rejected: list[dict[str, str]]


def eligible_ids(descriptor_hashes: dict[str, str], device_records: list[dict[str, object]]) -> set[str]:
    passed = {
        (str(record.get("effectID", "")).lower(), str(record.get("descriptorSHA256", "")).lower())
        for record in device_records
        if record.get("stage") == "device" and record.get("disposition") == "passed"
    }
    return {
        effect_id.lower()
        for effect_id, descriptor_hash in descriptor_hashes.items()
        if (effect_id.lower(), descriptor_hash.lower()) in passed
    }


def descriptor_hashes(app: Path) -> dict[str, str]:
    result: dict[str, str] = {}
    for path in sorted((app / "BuiltinEffects").glob("*.xml")):
        try:
            root = ET.fromstring(path.read_text(encoding="utf-8"))
        except ET.ParseError:
            continue
        effect_id = root.attrib.get("id", "").strip().lower()
        if effect_id:
            result[effect_id] = hashlib.sha256(path.read_bytes()).hexdigest()
    return result


def select_qualified_effects(
    app: Path,
    integrity_report: Path,
    ci_report: Path,
    device_report: Path,
) -> SelectionResult:
    hashes = descriptor_hashes(app)
    integrity = json.loads(integrity_report.read_text(encoding="utf-8"))
    ci = json.loads(ci_report.read_text(encoding="utf-8"))
    device = json.loads(device_report.read_text(encoding="utf-8"))

    safe_integrity = {
        str(record.get("effectID", "")).lower()
        for record in integrity.get("records", [])
        if record.get("status") in {"existingWorking", "implementedUnverified", "implementedVerified"}
            and not record.get("dependencies")
            and not record.get("resources")
            and not any(finding.get("severity") == "error" for finding in record.get("findings", []))
    }
    ci_by_id = {
        str(record.get("effectID", "")).lower(): record
        for record in ci.get("records", [])
    }
    exact_device = eligible_ids(hashes, device.get("records", []))

    selected: list[str] = []
    rejected: list[dict[str, str]] = []
    for effect_id, descriptor_hash in sorted(hashes.items()):
        if effect_id not in safe_integrity:
            rejected.append({"effectID": effect_id, "reason": "integrity_not_passed"})
            continue
        ci_record = ci_by_id.get(effect_id)
        if ci_record is None:
            rejected.append({"effectID": effect_id, "reason": "missing_ci_qualification"})
            continue
        if str(ci_record.get("descriptorSHA256", "")).lower() != descriptor_hash.lower():
            rejected.append({"effectID": effect_id, "reason": "stale_ci_hash"})
            continue
        if ci_record.get("disposition") == "failed":
            rejected.append({"effectID": effect_id, "reason": "ci_visual_failure"})
            continue
        if effect_id not in exact_device:
            rejected.append({"effectID": effect_id, "reason": "missing_exact_hash_device_pass"})
            continue
        selected.append(effect_id)

    return SelectionResult(selectedEffectIDs=selected, otherCount=len(selected), rejected=rejected)


def write_manifest(result: SelectionResult, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps({"schemaVersion": 3, **asdict(result)}, indent=2) + "\n", encoding="utf-8")
