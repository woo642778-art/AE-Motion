#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import html
import importlib.util
import json
import re
import shutil
import sys
from dataclasses import asdict, dataclass
from pathlib import Path
from xml.etree import ElementTree as ET

KNOWN_REPAIRS = {
    "com.alightcreative.effects.bccedgeglow": "bccedgeglow.xml",
    "com.alightcreative.effects.bbmaker": "blackbars.xml",
}
LARGE_LOOP_RE = re.compile(r"for\s*\([^;]*;\s*[^;]*(?:<=|<)\s*(?:128|192|256|512)(?:\.0)?", re.I)
ATTR_RE = re.compile(r"(?P<name>[A-Za-z_:][\w:.-]*)\s*=\s*(?P<quote>['\"])(?P<value>.*?)(?P=quote)", re.S)
EFFECT_RE = re.compile(r"<effect\b(?P<attrs>[^>]*)>", re.I | re.S)
SHADER_RE = re.compile(r"<shader\b[^>]*>(?P<body>.*?)</shader>", re.I | re.S)
_VISUAL_MODULE = None
DEVICE_GATED_VISUAL_CODES = {
    "fixed_opaque_alpha",
    "unbounded_texture_coordinates",
    "zero_permitted_divisor",
    "aspect_ratio_bounds_uncertain",
}


@dataclass(frozen=True)
class RuntimeFinding:
    code: str
    severity: str
    message: str


@dataclass(frozen=True)
class RuntimeRecord:
    effectID: str
    fileName: str
    action: str
    beforeSHA256: str
    afterSHA256: str | None
    findings: list[dict[str, str]]


def attrs(tag: str) -> dict[str, str]:
    return {m.group("name").lower(): m.group("value") for m in ATTR_RE.finditer(tag)}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def visual_module():
    global _VISUAL_MODULE
    if _VISUAL_MODULE is None:
        path = Path(__file__).with_name("effect-visual-qualification.py")
        spec = importlib.util.spec_from_file_location("aemotion_visual_qualification", path)
        if spec is None or spec.loader is None:
            raise RuntimeError("Unable to load visual qualification module")
        module = importlib.util.module_from_spec(spec)
        sys.modules[spec.name] = module
        spec.loader.exec_module(module)
        _VISUAL_MODULE = module
    return _VISUAL_MODULE


def analyze(path: Path) -> tuple[str, list[RuntimeFinding]]:
    text = path.read_text(encoding="utf-8")
    match = EFFECT_RE.search(text)
    if not match:
        return "", [RuntimeFinding("missing_effect_root", "error", "Descriptor has no effect root.")]
    effect_id = attrs(match.group(0)).get("id", "").strip()
    findings: list[RuntimeFinding] = []

    try:
        root = ET.fromstring(text)
    except ET.ParseError as error:
        findings.append(RuntimeFinding("xml_parse_failure", "error", str(error)))
        return effect_id, findings

    params = root.find("params")
    direct_ids: list[str] = []
    if params is not None:
        for element in list(params):
            value = element.attrib.get("id")
            if value:
                direct_ids.append(value)
    duplicates = sorted({value for value in direct_ids if direct_ids.count(value) > 1})
    if duplicates:
        findings.append(RuntimeFinding("duplicate_parameter_id", "error", f"Duplicate direct parameter IDs: {', '.join(duplicates)}"))

    shaders = [html.unescape(m.group("body")) for m in SHADER_RE.finditer(text)]
    combined_shader = "\n".join(shaders)
    if shaders and "gl_FragColor" not in combined_shader:
        findings.append(RuntimeFinding("shader_has_no_output", "error", "Fragment shader never assigns gl_FragColor."))
    if LARGE_LOOP_RE.search(combined_shader):
        findings.append(RuntimeFinding("high_risk_dynamic_loop", "error", "Shader contains a 128+ iteration loop that can trap or exhaust the mobile compiler."))

    buffers = {element.attrib.get("id", "") for element in root.iter("texture") if element.attrib.get("srcType", "").lower() == "buffer"}
    buffers.discard("")
    targets = {element.attrib.get("target", "") for element in root.iter("pass") if element.attrib.get("target")}
    missing_targets = sorted(targets - buffers)
    if missing_targets:
        findings.append(RuntimeFinding("missing_pass_buffer", "error", f"Pass targets undeclared buffers: {', '.join(missing_targets)}"))

    for element in root.iter():
        if element.tag.lower() not in {"spinner", "slider", "integer"}:
            continue
        try:
            minimum = float(element.attrib.get("min", "nan"))
            maximum = float(element.attrib.get("max", "nan"))
            default = float(element.attrib.get("default", "nan"))
            step_raw = element.attrib.get("step")
            if minimum == minimum and maximum == maximum and minimum > maximum:
                findings.append(RuntimeFinding("invalid_parameter_range", "error", f"{element.attrib.get('id', '?')} has min > max."))
            if default == default and minimum == minimum and maximum == maximum and not minimum <= default <= maximum:
                findings.append(RuntimeFinding("default_out_of_range", "error", f"{element.attrib.get('id', '?')} default is outside its range."))
            if step_raw is not None and float(step_raw) <= 0:
                findings.append(RuntimeFinding("invalid_parameter_step", "warning", f"{element.attrib.get('id', '?')} has a non-positive step."))
        except ValueError:
            findings.append(RuntimeFinding("invalid_numeric_parameter", "error", f"{element.attrib.get('id', '?')} has malformed numeric metadata."))

    for visual in visual_module().analyze_descriptor_text(text):
        code = str(visual.get("code", "visual_risk"))
        severity = "warning" if code in DEVICE_GATED_VISUAL_CODES else "error" if visual.get("confidence") == "high" else "warning"
        message = str(visual.get("message", "Visual qualification requires review."))
        if not any(item.code == code for item in findings):
            findings.append(RuntimeFinding(code, severity, message))

    return effect_id, findings


def repair_and_quarantine(app: Path, repair_dir: Path, manifest_path: Path) -> dict[str, object]:
    effects = app / "BuiltinEffects"
    quarantine = app / "AEMotionQuarantine" / "RuntimeEffects"
    quarantine.mkdir(parents=True, exist_ok=True)
    records: list[RuntimeRecord] = []

    by_id: dict[str, Path] = {}
    for path in effects.glob("*.xml"):
        match = EFFECT_RE.search(path.read_text(encoding="utf-8"))
        if match:
            effect_id = attrs(match.group(0)).get("id", "").strip().lower()
            if effect_id:
                by_id[effect_id] = path

    for effect_id, filename in KNOWN_REPAIRS.items():
        target = by_id.get(effect_id.lower())
        source = repair_dir / filename
        if target is None:
            raise FileNotFoundError(f"Known repair target is missing: {effect_id}")
        if not source.is_file():
            raise FileNotFoundError(f"Repair descriptor is missing: {source}")
        before = sha256(target)
        source_id, source_findings = analyze(source)
        errors = [finding for finding in source_findings if finding.severity == "error"]
        if source_id.lower() != effect_id.lower() or errors:
            raise RuntimeError(f"Repair validation failed for {effect_id}: {errors}")
        shutil.copy2(source, target)
        records.append(RuntimeRecord(effect_id, target.name, "repaired", before, sha256(target), [asdict(x) for x in source_findings]))

    for path in sorted(effects.glob("*.xml")):
        effect_id, findings = analyze(path)
        errors = [finding for finding in findings if finding.severity == "error"]
        if not errors:
            continue
        before = sha256(path)
        destination = quarantine / path.name
        if destination.exists():
            destination.unlink()
        shutil.move(str(path), destination)
        records.append(RuntimeRecord(effect_id, path.name, "quarantined", before, None, [asdict(x) for x in findings]))

    result = {
        "schemaVersion": 2,
        "release": "v2.2-beta19",
        "repaired": sum(record.action == "repaired" for record in records),
        "quarantined": sum(record.action == "quarantined" for record in records),
        "records": [asdict(record) for record in records],
    }
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    manifest_path.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("app", type=Path)
    parser.add_argument("--repairs", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    args = parser.parse_args()
    result = repair_and_quarantine(args.app.resolve(), args.repairs.resolve(), args.manifest.resolve())
    print(f"Repaired {result['repaired']} and quarantined {result['quarantined']} runtime-risk effects.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
