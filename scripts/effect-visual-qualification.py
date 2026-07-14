#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
from pathlib import Path
from xml.etree import ElementTree as ET

FIXED_OPAQUE_ALPHA_RE = re.compile(r"gl_FragColor\s*=\s*vec4\s*\([^;]+,\s*1(?:\.0+)?\s*\)", re.I | re.S)
UNBOUNDED_SAMPLE_RE = re.compile(r"texture2D(?:Cv)?\s*\([^,]+,\s*([^\)]*(?:acScreenNorm|\buv\b)[^\)]*)\)", re.I | re.S)
BORDER_BLACK_RE = re.compile(r"(?:step|smoothstep|if\s*\()[^;{}]*(?:acScreenNorm|\buv\b)[\s\S]{0,240}?(?:vec3|vec4)\s*\(\s*0(?:\.0+)?", re.I)
DIVISION_RE_TEMPLATE = r"/\s*{name}\b"
ASPECT_ONE_AXIS_RE = re.compile(r"getTexSize\s*\([^\)]*\)[\s\S]{0,180}?\.(?:x|y)[\s\S]{0,120}?(?:\*|/)", re.I)


def _effect_root(text: str) -> ET.Element:
    return ET.fromstring(text)


def analyze_descriptor_text(text: str) -> list[dict[str, str]]:
    findings: list[dict[str, str]] = []
    try:
        root = _effect_root(text)
    except ET.ParseError as error:
        return [{"code": "xml_parse_failure", "confidence": "high", "disposition": "failed", "message": str(error)}]
    tags = (root.attrib.get("tags", "") + " " + root.attrib.get("desc", "")).lower()
    declared_bars = any(token in tags for token in ("letterbox", "cinematic bars", "black bars"))
    shaders = "\n".join((node.text or "") for node in root.iter("shader"))
    samples_content = "texture2D" in shaders and any(
        node.attrib.get("srcType", "").lower() == "content" for node in root.iter("texture")
    )

    if samples_content and FIXED_OPAQUE_ALPHA_RE.search(shaders):
        findings.append({
            "code": "fixed_opaque_alpha",
            "confidence": "high",
            "disposition": "failed",
            "message": "The shader samples content but forces output alpha to 1.0.",
        })

    for match in UNBOUNDED_SAMPLE_RE.finditer(shaders):
        expression = match.group(1)
        if any(token in expression for token in ("clamp(", "fract(", "mod(")):
            continue
        if re.search(r"(?:acScreenNorm|\buv\b)\s*(?:\*|\+|\-)", expression):
            findings.append({
                "code": "unbounded_texture_coordinates",
                "confidence": "high",
                "disposition": "failed",
                "message": "Texture coordinates are scaled or offset without clamp, wrap or repeat handling.",
            })
            break

    if not declared_bars and BORDER_BLACK_RE.search(shaders):
        findings.append({
            "code": "implicit_black_border_mask",
            "confidence": "high",
            "disposition": "failed",
            "message": "The shader appears to mask frame borders to black without declaring a letterbox effect.",
        })

    for node in root.iter():
        if node.tag.lower() not in {"spinner", "slider", "integer"}:
            continue
        identifier = node.attrib.get("id", "")
        if not identifier:
            continue
        try:
            minimum = float(node.attrib.get("min", "nan"))
            maximum = float(node.attrib.get("max", "nan"))
        except ValueError:
            continue
        if minimum <= 0 <= maximum and re.search(DIVISION_RE_TEMPLATE.format(name=re.escape(identifier)), shaders):
            if not re.search(rf"max\s*\(\s*{re.escape(identifier)}\s*,\s*(?:0\.0*1|1e-\d+)", shaders, re.I):
                findings.append({
                    "code": "zero_permitted_divisor",
                    "confidence": "high",
                    "disposition": "failed",
                    "message": f"Parameter {identifier} permits zero and is used as an unguarded divisor.",
                })

    if ASPECT_ONE_AXIS_RE.search(shaders) and not any(token in shaders for token in ("clamp(", "fract(", "mod(")):
        findings.append({
            "code": "aspect_ratio_bounds_uncertain",
            "confidence": "medium",
            "disposition": "deviceQualificationRequired",
            "message": "Aspect-ratio correction changes one axis without explicit bounds handling.",
        })
    return findings


def analyze_descriptor_visual_risk(path: Path) -> dict[str, object]:
    text = path.read_text(encoding="utf-8")
    try:
        root = _effect_root(text)
        effect_id = root.attrib.get("id", "")
    except ET.ParseError:
        effect_id = ""
    findings = analyze_descriptor_text(text)
    high = any(item["confidence"] == "high" for item in findings)
    medium = any(item["confidence"] == "medium" for item in findings)
    disposition = "failed" if high else "deviceQualificationRequired" if medium else "passed"
    return {
        "effectID": effect_id,
        "fileName": path.name,
        "descriptorSHA256": hashlib.sha256(path.read_bytes()).hexdigest(),
        "stage": "ci",
        "disposition": disposition,
        "findings": findings,
    }


def _black(pixel: bytes) -> bool:
    return pixel[0] <= 5 and pixel[1] <= 5 and pixel[2] <= 5


def analyze_rgba_output(source: bytes, output: bytes, width: int, height: int) -> dict[str, object]:
    expected = width * height * 4
    if width <= 0 or height <= 0 or len(source) != expected or len(output) != expected:
        raise ValueError("rgba_size_mismatch")

    def pixel(data: bytes, x: int, y: int) -> bytes:
        offset = (y * width + x) * 4
        return data[offset:offset + 4]

    border_rows = max(1, int(round(height * 0.05)))
    border_cols = max(1, int(round(width * 0.05)))

    def ratio(coords: list[tuple[int, int]]) -> float:
        return sum(_black(pixel(output, x, y)) for x, y in coords) / max(len(coords), 1)

    top = [(x, y) for y in range(border_rows) for x in range(width)]
    bottom = [(x, y) for y in range(height - border_rows, height) for x in range(width)]
    left = [(x, y) for y in range(height) for x in range(border_cols)]
    right = [(x, y) for y in range(height) for x in range(width - border_cols, width)]
    x0, x1 = width // 4, max(width // 4 + 1, width * 3 // 4)
    y0, y1 = height // 4, max(height // 4 + 1, height * 3 // 4)
    center = [(x, y) for y in range(y0, y1) for x in range(x0, x1)]

    pixels = [output[index:index + 4] for index in range(0, len(output), 4)]
    black_ratio = sum(_black(item) for item in pixels) / len(pixels)
    transparent_ratio = sum(item[3] <= 1 for item in pixels) / len(pixels)
    partial_indices = [index for index in range(width * height) if 0 < source[index * 4 + 3] < 255]
    alpha_loss_ratio = (
        sum(output[index * 4 + 3] in {0, 255} for index in partial_indices) / len(partial_indices)
        if partial_indices else 0.0
    )

    metrics = {
        "topBlackRatio": ratio(top),
        "bottomBlackRatio": ratio(bottom),
        "leftBlackRatio": ratio(left),
        "rightBlackRatio": ratio(right),
        "centerBlackRatio": ratio(center),
        "transparentRatio": transparent_ratio,
        "alphaLossRatio": alpha_loss_ratio,
        "blackRatio": black_ratio,
    }
    findings: list[dict[str, object]] = []
    if metrics["centerBlackRatio"] < 0.50:
        for edge in ("top", "bottom", "left", "right"):
            value = metrics[f"{edge}BlackRatio"]
            if value >= 0.92:
                findings.append({"code": "unexpected_black_bar", "edge": edge, "ratio": value})
    if black_ratio >= 0.995:
        findings.append({"code": "blank_black_output", "ratio": black_ratio})
    if transparent_ratio >= 0.995:
        findings.append({"code": "blank_transparent_output", "ratio": transparent_ratio})
    if partial_indices and len(partial_indices) / (width * height) >= 0.05 and alpha_loss_ratio >= 0.90:
        findings.append({"code": "alpha_loss", "ratio": alpha_loss_ratio})
    return {"disposition": "passed" if not findings else "failed", "findings": findings, "metrics": metrics}


def qualify_app(app: Path, integrity_report: Path | None, output: Path) -> dict[str, object]:
    effects = app / "BuiltinEffects"
    quarantine = app / "AEMotionQuarantine" / "VisualEffects"
    quarantine.mkdir(parents=True, exist_ok=True)
    allowed: set[str] | None = None
    if integrity_report and integrity_report.is_file():
        report = json.loads(integrity_report.read_text(encoding="utf-8"))
        allowed = {
            str(record.get("effectID", "")).lower()
            for record in report.get("records", [])
            if record.get("status") in {"existingWorking", "implementedUnverified", "implementedVerified"}
        }
    records: list[dict[str, object]] = []
    quarantined = 0
    for path in sorted(effects.glob("*.xml")):
        record = analyze_descriptor_visual_risk(path)
        if allowed is not None and str(record["effectID"]).lower() not in allowed:
            continue
        if record["disposition"] == "failed":
            destination = quarantine / path.name
            if destination.exists():
                destination.unlink()
            shutil.move(str(path), destination)
            record["action"] = "quarantined"
            quarantined += 1
        else:
            record["action"] = "retained"
        records.append(record)
    result = {"schemaVersion": 1, "stage": "ci", "records": records, "quarantined": quarantined}
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("app", type=Path)
    parser.add_argument("--integrity-report", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = qualify_app(args.app.resolve(), args.integrity_report, args.output.resolve())
    print(f"Qualified {len(result['records'])} descriptors; quarantined {result['quarantined']} visual risks.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
