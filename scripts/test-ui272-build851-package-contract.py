#!/usr/bin/env python3
from pathlib import Path
import ast
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
packager = (ROOT / "scripts/package-ui272-build851-ipa.py").read_text(encoding="utf-8")
build = (ROOT / "scripts/build-ios-framework.sh").read_text(encoding="utf-8")
release = (ROOT / "Sources/AEMotionExtensionsCore/AEMotionRelease.swift").read_text(encoding="utf-8")

checks = {
    "Build 851 package number": (packager, r"BUILD_NUMBER\s*=\s*851"),
    "Build 851 display name": (packager, r"AE Motion 851"),
    "official URL": (packager, r"https://t\.me/aemotionios"),
    "legacy Blatant token check": (packager, r"b\"Blatant\""),
    "legacy Cracked By token check": (packager, r"b\"Cracked By\""),
    "legacy URL token check": (packager, r"b\"t\.me/blatants\""),
    "UTF-16 verification": (packager, r"encode\(\"utf-16le\"\)"),
    "host section preservation": (packager, r"first_section_offset.*section bytes changed"),
    "single UI load": (packager, r"count\(module\.UI_LOAD_PATH\)\s*!=\s*1"),
    "existing extension load": (packager, r"EXISTING_EXTENSION_LOAD_PATH"),
    "framework metadata": (packager, r"CFBundleVersion.*851"),
    "Build 851 framework": (build, r"CFBundleVersion\": \"851\""),
    "Build 851 release": (release, r"buildNumber\s*=\s*851"),
}

failed = [
    name
    for name, (text, pattern) in checks.items()
    if re.search(pattern, text, re.S | re.I) is None
]

parsed = ast.parse(packager)
replacements = None
for node in parsed.body:
    if isinstance(node, ast.Assign):
        if any(isinstance(target, ast.Name) and target.id == "BYTE_SAFE_BRANDING_REPLACEMENTS" for target in node.targets):
            replacements = ast.literal_eval(node.value)
            break
if not replacements:
    failed.append("byte-safe replacement table")
else:
    for old_text, new_text in replacements:
        if len(old_text.encode("utf-8")) != len(new_text.encode("utf-8")):
            failed.append(f"UTF-8 replacement length: {old_text}")
        if len(old_text.encode("utf-16le")) != len(new_text.encode("utf-16le")):
            failed.append(f"UTF-16 replacement length: {old_text}")

forbidden = {
    "initializer patch": r"INITIALIZER_LOCAL_OFFSET|PROMOTION_INITIALIZER|RETURN_INSTRUCTION",
    "legacy loader": r"AEMotionLegacy|LegacyFrameworkLoader",
    "framework byte-string version hack": r"Build 846.*Build 851",
}
for name, pattern in forbidden.items():
    if re.search(pattern, packager, re.S):
        failed.append(name)

if failed:
    print("FAIL: " + ", ".join(failed))
    sys.exit(1)
print("PASS: Build 851 packaging contract")
