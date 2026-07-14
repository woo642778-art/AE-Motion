#!/usr/bin/env python3
from __future__ import annotations

import argparse
import html
import json
import re
import zipfile
from dataclasses import asdict, dataclass
from enum import Enum
from pathlib import Path
from xml.etree import ElementTree as ET


class FindingCode(str, Enum):
    XML_PARSE_FAILURE = "xml_parse_failure"
    DUPLICATE_PARAMETER_ID = "duplicate_parameter_id"
    INVALID_PARAMETER_RANGE = "invalid_parameter_range"
    DEFAULT_OUT_OF_RANGE = "default_out_of_range"
    INVALID_PARAMETER_STEP = "invalid_parameter_step"
    MISSING_SHADER_OUTPUT = "missing_shader_output"
    UNSAFE_LOOP = "unsafe_loop"
    ZERO_PERMITTED_DIVISOR = "zero_permitted_divisor"
    MISSING_TEXTURE = "missing_texture"
    MISSING_PASS_BUFFER = "missing_pass_buffer"
    MISSING_RESOURCE = "missing_resource"
    TEXTURE_COORDINATE_RISK = "texture_coordinate_risk"
    ASPECT_RATIO_RISK = "aspect_ratio_risk"
    ALPHA_DESTRUCTION = "alpha_destruction"
    BLANK_DEFAULT_OUTPUT = "blank_default_output"
    UNINTENDED_BORDER_BARS = "unintended_border_bars"
    INVALID_THUMBNAIL = "invalid_thumbnail"
    UNSUPPORTED_DEPENDENCY = "unsupported_dependency"


@dataclass(frozen=True)
class Finding:
    code: str
    severity: str
    evidence: str


@dataclass(frozen=True)
class QueueRecord:
    effectID: str
    fileName: str
    originalCategory: str
    baselineDescriptorSHA256: str
    findings: list[dict[str, str]]
    repairFamily: str
    status: str
    repairDescriptorSHA256: str | None
    deviceQualificationRequired: bool


class SemanticExceptions:
    def __init__(self, effects: dict[str, dict[str, object]]):
        self._effects = {key.lower(): value for key, value in effects.items()}

    def permits(self, effect_id: str, code: str) -> bool:
        record = self._effects.get(effect_id.lower(), {})
        allowed = record.get("allowedFindings", [])
        return code in allowed


def load_semantic_exceptions(payload: dict[str, object]) -> SemanticExceptions:
    effects = payload.get("effects", {})
    if not isinstance(effects, dict):
        raise ValueError("semantic exceptions effects must be an object")
    for effect_id in effects:
        if "*" in effect_id:
            raise ValueError("wildcard semantic exceptions are not allowed")
    return SemanticExceptions(effects)


LOOP_RE = re.compile(r"for\s*\([^;]*;\s*[^;]*(?:<|<=)\s*(128|192|256|512)(?:\.0)?", re.I)
DIVISOR_RE = re.compile(r"/\s*([A-Za-z_]\w*)")
TEXTURE_USE_RE = re.compile(r"texture2D(?:Cv)?\s*\(\s*([A-Za-z_]\w*)\.texture", re.I)


def _numeric_controls(root: ET.Element) -> dict[str, tuple[float | None, float | None, float | None]]:
    controls: dict[str, tuple[float | None, float | None, float | None]] = {}
    for element in root.iter():
        if element.tag.lower() not in {"slider", "spinner", "integer"}:
            continue
        identifier = element.attrib.get("id", "").strip()
        if not identifier:
            continue

        def number(name: str) -> float | None:
            try:
                return float(element.attrib[name])
            except (KeyError, ValueError):
                return None

        controls[identifier] = (number("min"), number("max"), number("default"))
    return controls


def classify_descriptor(xml: str) -> list[Finding]:
    findings: list[Finding] = []
    try:
        root = ET.fromstring(xml)
    except ET.ParseError as error:
        return [Finding(FindingCode.XML_PARSE_FAILURE.value, "error", str(error))]

    ids = [element.attrib["id"] for element in root.iter() if element.attrib.get("id")]
    duplicates = sorted({identifier for identifier in ids if ids.count(identifier) > 1})
    if duplicates:
        findings.append(Finding(FindingCode.DUPLICATE_PARAMETER_ID.value, "error", ", ".join(duplicates)))

    controls = _numeric_controls(root)
    for identifier, (minimum, maximum, default) in controls.items():
        element = next((item for item in root.iter() if item.attrib.get("id") == identifier), None)
        if minimum is not None and maximum is not None and minimum > maximum:
            findings.append(Finding(FindingCode.INVALID_PARAMETER_RANGE.value, "error", identifier))
        if minimum is not None and maximum is not None and default is not None and not minimum <= default <= maximum:
            findings.append(Finding(FindingCode.DEFAULT_OUT_OF_RANGE.value, "error", identifier))
        if element is not None and "step" in element.attrib:
            try:
                if float(element.attrib["step"]) <= 0:
                    findings.append(Finding(FindingCode.INVALID_PARAMETER_STEP.value, "error", identifier))
            except ValueError:
                findings.append(Finding(FindingCode.INVALID_PARAMETER_STEP.value, "error", identifier))

    shader_bodies = [html.unescape(element.text or "") for element in root.iter() if element.tag.lower() == "shader"]
    shader = "\n".join(shader_bodies)
    if shader_bodies and "gl_FragColor" not in shader:
        findings.append(Finding(FindingCode.MISSING_SHADER_OUTPUT.value, "error", "fragment shader does not assign gl_FragColor"))
    loop = LOOP_RE.search(shader)
    if loop:
        findings.append(Finding(FindingCode.UNSAFE_LOOP.value, "error", f"constant loop upper bound {loop.group(1)}"))

    for divisor in sorted(set(DIVISOR_RE.findall(shader))):
        limits = controls.get(divisor)
        if limits is None:
            continue
        minimum, maximum, default = limits
        if minimum is not None and maximum is not None and minimum <= 0 <= maximum:
            findings.append(Finding(FindingCode.ZERO_PERMITTED_DIVISOR.value, "error", f"{divisor} permits zero"))
        elif default == 0:
            findings.append(Finding(FindingCode.ZERO_PERMITTED_DIVISOR.value, "error", f"{divisor} defaults to zero"))

    textures = {element.attrib.get("id", "") for element in root.iter() if element.tag.lower() == "texture"}
    textures.discard("")
    buffers = {
        element.attrib.get("id", "")
        for element in root.iter()
        if element.tag.lower() == "texture" and element.attrib.get("srcType", "").lower() == "buffer"
    }
    pass_targets = {
        element.attrib.get("target", "")
        for element in root.iter()
        if element.tag.lower() == "pass" and element.attrib.get("target")
    }
    for target in sorted(pass_targets - buffers):
        findings.append(Finding(FindingCode.MISSING_PASS_BUFFER.value, "error", target))
    sampled = set(TEXTURE_USE_RE.findall(shader))
    for texture in sorted(sampled - textures):
        findings.append(Finding(FindingCode.MISSING_TEXTURE.value, "error", texture))

    root_text = ET.tostring(root, encoding="unicode")
    thumb = root.attrib.get("thumb", "").strip()
    if thumb and (thumb.startswith("/") or ".." in Path(thumb).parts):
        findings.append(Finding(FindingCode.INVALID_THUMBNAIL.value, "error", thumb))

    if re.search(r"gl_FragColor\s*=\s*vec4\s*\([^,]+,[^,]+,[^,]+,\s*1(?:\.0)?\s*\)", shader):
        findings.append(Finding(FindingCode.ALPHA_DESTRUCTION.value, "warning", "fragment output forces alpha to one"))
    if "acScreenNorm" in shader and re.search(r"acScreenNorm\s*[*/+-]\s*[A-Za-z_]", shader):
        findings.append(Finding(FindingCode.TEXTURE_COORDINATE_RISK.value, "warning", "screen coordinates are transformed without explicit clamp"))
    if "getTexSize" in shader and any(token in shader for token in ("aspect", "ratio", "/ getTexSize", "/getTexSize")):
        findings.append(Finding(FindingCode.ASPECT_RATIO_RISK.value, "warning", "aspect calculations require fixture verification"))
    if re.search(r"gl_FragColor\s*=\s*vec4\s*\(\s*0(?:\.0)?\s*\)", shader):
        findings.append(Finding(FindingCode.BLANK_DEFAULT_OUTPUT.value, "warning", "shader contains an unconditional blank output expression"))
    if "black" in root.attrib.get("name", "").lower() and "bar" in root.attrib.get("name", "").lower():
        findings.append(Finding(FindingCode.UNINTENDED_BORDER_BARS.value, "warning", "bar effect requires neutral-default fixture verification"))
    if any(key in root_text.lower() for key in ("plugin=", "externaldependency", "nativeplugin")):
        findings.append(Finding(FindingCode.UNSUPPORTED_DEPENDENCY.value, "error", "descriptor declares an unsupported external dependency"))

    unique: dict[tuple[str, str], Finding] = {}
    for finding in findings:
        unique[(finding.code, finding.evidence)] = finding
    return sorted(unique.values(), key=lambda item: (item.code, item.evidence))


def repair_family(findings: list[Finding], record: dict[str, object]) -> str:
    codes = {finding.code for finding in findings}
    if codes & {
        FindingCode.XML_PARSE_FAILURE.value,
        FindingCode.DUPLICATE_PARAMETER_ID.value,
        FindingCode.INVALID_PARAMETER_RANGE.value,
        FindingCode.DEFAULT_OUT_OF_RANGE.value,
        FindingCode.INVALID_PARAMETER_STEP.value,
    }:
        return "metadata_xml"
    if codes & {FindingCode.MISSING_PASS_BUFFER.value, FindingCode.MISSING_TEXTURE.value}:
        return "multi_pass_buffer"
    if codes & {FindingCode.MISSING_RESOURCE.value, FindingCode.UNSUPPORTED_DEPENDENCY.value}:
        return "resource_procedural"
    if codes & {FindingCode.UNSAFE_LOOP.value, FindingCode.MISSING_SHADER_OUTPUT.value}:
        return "multi_pass_buffer" if record.get("passes") else "single_pass_shader"
    if codes & {FindingCode.ZERO_PERMITTED_DIVISOR.value}:
        return "parameter_numerical"
    if codes & {
        FindingCode.ALPHA_DESTRUCTION.value,
        FindingCode.TEXTURE_COORDINATE_RISK.value,
        FindingCode.ASPECT_RATIO_RISK.value,
        FindingCode.BLANK_DEFAULT_OUTPUT.value,
        FindingCode.UNINTENDED_BORDER_BARS.value,
        FindingCode.INVALID_THUMBNAIL.value,
    }:
        return "alpha_aspect_border"
    return "static_revalidation"


def build_queue(
    baseline: dict[str, object],
    descriptor_texts: dict[str, str],
    beta19_missing_ids: set[str],
) -> list[QueueRecord]:
    records = baseline.get("records", [])
    normalized_missing = {item.lower() for item in beta19_missing_ids}
    queue: list[QueueRecord] = []
    for record in records:
        effect_id = str(record["effectID"])
        missing = (
            "/AEMotionQuarantine/" in str(record.get("sourceLocation", ""))
            or effect_id.lower() in normalized_missing
        )
        if not missing:
            continue
        findings = classify_descriptor(descriptor_texts.get(effect_id.lower(), descriptor_texts.get(effect_id, "")))
        queue.append(
            QueueRecord(
                effectID=effect_id,
                fileName=str(record["fileName"]),
                originalCategory=str(record["originalCategory"]).strip().lower(),
                baselineDescriptorSHA256=str(record["descriptorSHA256"]),
                findings=[asdict(item) for item in findings],
                repairFamily=repair_family(findings, record),
                status="unrepaired",
                repairDescriptorSHA256=None,
                deviceQualificationRequired=True,
            )
        )
    return sorted(queue, key=lambda item: item.effectID.lower())


def _descriptor_texts_from_ipa(ipa_path: Path, baseline: dict[str, object]) -> dict[str, str]:
    output: dict[str, str] = {}
    with zipfile.ZipFile(ipa_path) as archive:
        for record in baseline["records"]:
            output[str(record["effectID"]).lower()] = archive.read(str(record["sourceLocation"])).decode("utf-8")
    return output


def main() -> int:
    parser = argparse.ArgumentParser(description="Classify the complete Beta 20 restoration queue.")
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--baseline-ipa", type=Path, required=True)
    parser.add_argument("--beta19-quarantined-ids", type=Path, required=True)
    parser.add_argument("--semantic-exceptions", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--require-count", type=int, default=130)
    args = parser.parse_args()

    baseline = json.loads(args.baseline.read_text(encoding="utf-8"))
    missing_payload = json.loads(args.beta19_quarantined_ids.read_text(encoding="utf-8"))
    beta19_missing_ids = set(missing_payload.get("effectIDs", []))
    load_semantic_exceptions(json.loads(args.semantic_exceptions.read_text(encoding="utf-8")))
    texts = _descriptor_texts_from_ipa(args.baseline_ipa, baseline)
    queue = build_queue(baseline, texts, beta19_missing_ids)
    if len(queue) != args.require_count:
        raise SystemExit(f"Repair queue count mismatch: expected {args.require_count}, found {len(queue)}")
    payload = {
        "schemaVersion": 1,
        "baselineEffectCount": baseline.get("effectCount"),
        "repairCount": len(queue),
        "records": [asdict(item) for item in queue],
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    families: dict[str, int] = {}
    for item in queue:
        families[item.repairFamily] = families.get(item.repairFamily, 0) + 1
    print(f"Repair queue: {len(queue)}")
    print("Repair families: " + json.dumps(dict(sorted(families.items()))))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
