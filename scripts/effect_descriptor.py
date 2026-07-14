#!/usr/bin/env python3
from __future__ import annotations

from dataclasses import dataclass
from hashlib import sha256
from pathlib import Path
from xml.etree import ElementTree as ET
import re

_NUMERIC_KINDS = {"slider", "spinner"}
_IGNORED_PARAMETER_TAGS = {"section", "tip", "iterations", "strings"}


@dataclass(frozen=True)
class Finding:
    code: str
    severity: str
    message: str


@dataclass(frozen=True)
class Parameter:
    parameter_id: str
    kind: str
    default: str | None = None
    minimum: str | None = None
    maximum: str | None = None
    step: str | None = None


@dataclass(frozen=True)
class EffectDescriptor:
    path: Path
    effect_id: str
    name: str
    category: str
    parameters: tuple[Parameter, ...]
    dependencies: tuple[str, ...]
    resources: tuple[str, ...]
    descriptor_sha256: str
    shader_sha256: str | None
    shader_text: str
    findings: tuple[Finding, ...]
    deprecated: bool

    def parameter_signature(self) -> str:
        return ",".join(
            f"{item.parameter_id}:{item.kind}"
            for item in sorted(self.parameters, key=lambda value: value.parameter_id)
        )


def _local_name(tag: str) -> str:
    return tag.split("}")[-1].lower()


def _float(value: str | None) -> float | None:
    if value is None:
        return None
    try:
        return float(value)
    except ValueError:
        return None


def _bool(value: str | None) -> bool:
    return (value or "").strip().lower() in {"1", "true", "yes"}


def _shader_text(root: ET.Element) -> str:
    parts: list[str] = []
    for node in root.iter():
        if _local_name(node.tag) in {"shader", "script"}:
            parts.append("".join(node.itertext()))
    return "\n".join(parts).strip()


def parse_effect(path: Path) -> EffectDescriptor:
    raw = path.read_bytes()
    root = ET.fromstring(raw)
    if _local_name(root.tag) != "effect":
        raise ValueError(f"{path}: root element is not <effect>")

    findings: list[Finding] = []
    effect_id = root.attrib.get("id", "").strip()
    name = root.attrib.get("name", "").strip()
    category = root.attrib.get("category", "").strip().lower()
    deprecated = _bool(root.attrib.get("deprecated"))

    if not effect_id:
        findings.append(Finding("missing_effect_id", "blocker", "Effect ID is missing."))
    if not name:
        severity = "blocker" if deprecated else "error"
        findings.append(Finding("missing_name", severity, "Display name is missing."))
    if not category:
        findings.append(Finding("missing_category", "blocker", "Category is missing."))

    parameters: list[Parameter] = []
    seen_parameter_ids: set[str] = set()
    params = next((node for node in root if _local_name(node.tag) == "params"), None)
    if params is not None:
        for node in list(params):
            kind = _local_name(node.tag)
            if kind in _IGNORED_PARAMETER_TAGS:
                continue
            parameter_id = node.attrib.get("id", "").strip()
            if not parameter_id:
                continue
            if parameter_id in seen_parameter_ids:
                findings.append(Finding(
                    "duplicate_parameter_id", "blocker",
                    f"Duplicate parameter ID: {parameter_id}"
                ))
            seen_parameter_ids.add(parameter_id)
            parameter = Parameter(
                parameter_id=parameter_id,
                kind=kind,
                default=node.attrib.get("default"),
                minimum=node.attrib.get("min"),
                maximum=node.attrib.get("max"),
                step=node.attrib.get("step"),
            )
            parameters.append(parameter)

            if kind in _NUMERIC_KINDS:
                minimum = _float(parameter.minimum)
                maximum = _float(parameter.maximum)
                default = _float(parameter.default)
                step = _float(parameter.step)
                if minimum is None or maximum is None or minimum > maximum:
                    findings.append(Finding(
                        "invalid_parameter_range", "blocker",
                        f"{parameter_id} has an invalid numeric range."
                    ))
                elif default is None or not minimum <= default <= maximum:
                    findings.append(Finding(
                        "invalid_parameter_default", "blocker",
                        f"{parameter_id} default is outside its range."
                    ))
                if step is None or step <= 0:
                    findings.append(Finding(
                        "invalid_parameter_step", "error",
                        f"{parameter_id} has no positive step."
                    ))
            elif kind == "selector":
                choices = {
                    choice.attrib.get("value", "").strip()
                    for choice in node
                    if _local_name(choice.tag) == "choice"
                }
                default = (parameter.default or "").strip()
                if not choices:
                    findings.append(Finding(
                        "selector_without_choices", "blocker",
                        f"{parameter_id} has no choices."
                    ))
                elif default not in choices:
                    findings.append(Finding(
                        "invalid_selector_default", "blocker",
                        f"{parameter_id} default is not a declared choice."
                    ))

    dependencies = tuple(sorted({
        node.attrib["effect"].strip()
        for node in root.iter()
        if _local_name(node.tag) == "pass" and node.attrib.get("effect", "").strip()
    }))

    resources: set[str] = set()
    for node in root.iter():
        if _local_name(node.tag) != "texture":
            continue
        value = node.attrib.get("src", "").strip()
        if value and not value.startswith(("content:", "builtin:", "@")):
            resources.add(value)

    for resource in sorted(resources):
        if not (path.parent / resource).is_file():
            findings.append(Finding(
                "missing_resource", "blocker",
                f"External resource is missing: {resource}"
            ))

    shader_text = _shader_text(root)
    shader_hash = sha256(shader_text.encode("utf-8")).hexdigest() if shader_text else None
    pass_nodes = [node for node in root.iter() if _local_name(node.tag) == "pass"]
    if shader_hash is None and not dependencies and not pass_nodes:
        findings.append(Finding(
            "missing_renderer_body", "blocker",
            "Effect has neither a shader/script body nor a render pass."
        ))

    if re.search(r"\bwhile\s*\(\s*(?:true|1)\s*\)", shader_text, re.IGNORECASE) \
            or re.search(r"\bfor\s*\(\s*;\s*;\s*\)", shader_text):
        findings.append(Finding(
            "obvious_unbounded_loop", "blocker",
            "Shader contains an obviously unbounded loop."
        ))

    return EffectDescriptor(
        path=path,
        effect_id=effect_id,
        name=name,
        category=category,
        parameters=tuple(parameters),
        dependencies=dependencies,
        resources=tuple(sorted(resources)),
        descriptor_sha256=sha256(raw).hexdigest(),
        shader_sha256=shader_hash,
        shader_text=shader_text,
        findings=tuple(findings),
        deprecated=deprecated,
    )
