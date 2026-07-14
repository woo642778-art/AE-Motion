#!/usr/bin/env python3
from __future__ import annotations

import argparse
from collections import defaultdict
from datetime import datetime, timezone
from hashlib import sha256
import json
from pathlib import Path
import plistlib
import re

from effect_descriptor import EffectDescriptor, Finding, parse_effect


def normalized_name(value: str) -> str:
    value = re.sub(r"[^a-z0-9]+", " ", value.lower())
    value = re.sub(r"\b(pro|plus|new|beta|v[0-9]+)\b", " ", value)
    return " ".join(value.split())


def functional_signature(effect: EffectDescriptor) -> str:
    payload = "|".join((
        normalized_name(effect.name),
        effect.category,
        effect.parameter_signature(),
        effect.shader_sha256 or "",
        ",".join(effect.dependencies),
    ))
    return sha256(payload.encode("utf-8")).hexdigest()


def _record(effect: EffectDescriptor, status: str, findings: list[Finding], reason: str | None) -> dict:
    return {
        "effectID": effect.effect_id,
        "name": effect.name,
        "fileName": effect.path.name,
        "category": effect.category,
        "status": status,
        "descriptorSHA256": effect.descriptor_sha256,
        "shaderSHA256": effect.shader_sha256,
        "parameterSignature": effect.parameter_signature(),
        "dependencies": list(effect.dependencies),
        "resources": list(effect.resources),
        "findings": [
            {"code": item.code, "severity": item.severity, "message": item.message}
            for item in findings
        ],
        "quarantineReason": reason,
    }


def audit_directory(target: Path) -> dict:
    target = target.resolve()
    app = target if target.suffix == ".app" else None
    if app:
        effects_dir = target / "BuiltinEffects"
    elif (target / "BuiltinEffects").is_dir():
        effects_dir = target / "BuiltinEffects"
    else:
        effects_dir = target
    if not effects_dir.is_dir():
        raise FileNotFoundError(f"BuiltinEffects directory not found: {effects_dir}")

    parsed: list[EffectDescriptor] = []
    parse_failures: list[tuple[Path, str]] = []
    for path in sorted(effects_dir.glob("*.xml"), key=lambda item: item.name.casefold()):
        try:
            parsed.append(parse_effect(path))
        except Exception as error:
            parse_failures.append((path, str(error)))

    by_id: dict[str, list[EffectDescriptor]] = defaultdict(list)
    for effect in parsed:
        by_id[effect.effect_id].append(effect)
    duplicate_ids = {key for key, values in by_id.items() if key and len(values) > 1}
    all_ids = {effect.effect_id for effect in parsed if effect.effect_id}

    by_signature: dict[str, list[EffectDescriptor]] = defaultdict(list)
    for effect in parsed:
        if effect.name:
            by_signature[functional_signature(effect)].append(effect)
    exact_duplicates = {
        effect.path
        for values in by_signature.values()
        if len(values) > 1
        for effect in values
    }

    records: list[dict] = []
    for effect in parsed:
        findings = list(effect.findings)
        status = "existingWorking"
        reason: str | None = None

        unresolved = [value for value in effect.dependencies if value not in all_ids]
        if unresolved:
            for value in unresolved:
                findings.append(Finding(
                    "missing_dependency", "blocker",
                    f"Helper effect dependency is missing: {value}"
                ))

        if effect.path in exact_duplicates:
            findings.append(Finding(
                "functional_duplicate_candidate", "warning",
                "Another descriptor has the same normalized name, parameter signature and shader hash."
            ))

        localized_native = effect.name.startswith(("@am:string/", "@string/"))
        if localized_native:
            downgraded: list[Finding] = []
            for item in findings:
                if item.code in {"missing_renderer_body", "invalid_selector_default"}:
                    downgraded.append(Finding(item.code, "warning", item.message))
                else:
                    downgraded.append(item)
            findings = downgraded

        codes = {item.code for item in findings}
        blocker_codes = {item.code for item in findings if item.severity == "blocker"}
        placeholder_name = not effect.name or normalized_name(effect.name) in {"test", "sample", "placeholder"}
        placeholder_file = any(token in effect.path.stem.lower() for token in ("placeholder", "example", "fixture"))

        if effect.effect_id in duplicate_ids:
            status, reason = "duplicate", "duplicate_effect_id"
        elif placeholder_name or placeholder_file:
            status, reason = "placeholder", "missing_or_placeholder_name"
        elif "missing_dependency" in codes or "missing_resource" in codes:
            status, reason = "unsupportedDependency", "missing_dependency_or_resource"
        elif blocker_codes:
            status, reason = "existingBroken", sorted(blocker_codes)[0]

        records.append(_record(effect, status, findings, reason))

    while True:
        unsafe_ids = {
            record["effectID"]
            for record in records
            if record["effectID"] and record["status"] not in {
                "existingWorking", "implementedUnverified", "implementedVerified"
            }
        }
        changed = False
        for record in records:
            if record["status"] != "existingWorking":
                continue
            blocked = sorted(set(record["dependencies"]) & unsafe_ids)
            if not blocked:
                continue
            record["status"] = "unsupportedDependency"
            record["quarantineReason"] = "quarantined_dependency"
            record["findings"].append({
                "code": "quarantined_dependency",
                "severity": "blocker",
                "message": "Required helper effect is unsafe: " + ", ".join(blocked),
            })
            changed = True
        if not changed:
            break

    for path, error in parse_failures:
        raw = path.read_bytes()
        records.append({
            "effectID": "",
            "name": path.stem,
            "fileName": path.name,
            "category": "",
            "status": "existingBroken",
            "descriptorSHA256": sha256(raw).hexdigest(),
            "shaderSHA256": None,
            "parameterSignature": "",
            "dependencies": [],
            "resources": [],
            "findings": [{
                "code": "xml_parse_failure",
                "severity": "blocker",
                "message": error,
            }],
            "quarantineReason": "xml_parse_failure",
        })

    info: dict = {}
    if app and (app / "Info.plist").is_file():
        with (app / "Info.plist").open("rb") as handle:
            info = plistlib.load(handle)

    records.sort(key=lambda item: (item["fileName"].casefold(), item["effectID"]))
    return {
        "schemaVersion": 1,
        "generatedAt": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "sourceAppVersion": str(info.get("CFBundleShortVersionString", "unknown")),
        "sourceBuild": str(info.get("CFBundleVersion", "unknown")),
        "records": records,
    }


def _summary(report: dict) -> str:
    counts: dict[str, int] = defaultdict(int)
    for record in report["records"]:
        counts[record["status"]] += 1
    lines = [f"Scanned: {len(report['records'])}"]
    for key in sorted(counts):
        lines.append(f"{key}: {counts[key]}")
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("target", type=Path, help="AlightMotion.app or BuiltinEffects directory")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--summary", type=Path)
    args = parser.parse_args()

    report = audit_directory(args.target)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, sort_keys=False) + "\n", encoding="utf-8")
    text = _summary(report)
    if args.summary:
        args.summary.parent.mkdir(parents=True, exist_ok=True)
        args.summary.write_text(text, encoding="utf-8")
    print(text, end="")

    has_parse = any(
        finding["code"] == "xml_parse_failure"
        for record in report["records"]
        for finding in record["findings"]
    )
    has_duplicate_id = any(
        record["quarantineReason"] == "duplicate_effect_id"
        for record in report["records"]
    )
    if has_parse:
        return 3
    if has_duplicate_id:
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
