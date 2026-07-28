#!/usr/bin/env python3
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
packager = (ROOT / "scripts/package-ui272-build852-ipa.py").read_text(encoding="utf-8")
release = (ROOT / "Sources/AEMotionExtensionsCore/AEMotionRelease.swift").read_text(encoding="utf-8")
build = (ROOT / "scripts/build-ios-framework.sh").read_text(encoding="utf-8")

checks = {
    "Build 852 package number": (packager, r"BUILD_NUMBER\s*=\s*852"),
    "Build 852 release number": (release, r"buildNumber\s*=\s*852"),
    "Build 852 framework number": (build, r'CFBundleVersion": "852"'),
    "remove legacy promotion load": (packager, r"remove_load_dylib.*LEGACY_PROMOTION_LOAD_PATH"),
    "remove legacy promotion file": (packager, r"LEGACY_PROMOTION_RELATIVE.*unlink\(\)"),
    "preserve extension framework": (packager, r"EXTENSION_RELATIVE"),
    "disable old launch overlay": (packager, r"0x190CB0.*c0035fd6"),
    "disable old home resolver": (packager, r"0x2A2E80.*000080d2c0035fd6"),
    "disable old tutorials resolver": (packager, r"0x2A2F74.*000080d2c0035fd6"),
    "disable old projects resolver": (packager, r"0x2A3250.*000080d2c0035fd6"),
    "disable old templates resolver": (packager, r"0x2A3344.*000080d2c0035fd6"),
    "disable legacy surface refresh": (packager, r"0x2A3DA0.*c0035fd6"),
    "zero forbidden branding": (packager, r"FORBIDDEN_PROMOTION_TOKENS.*forbidden promotion token remains"),
    "official Telegram": (packager, r"https://t\.me/aemotionios"),
    "host code section preservation": (packager, r"first_section_offset.*section bytes changed"),
}

failed = [
    name
    for name, (text, pattern) in checks.items()
    if re.search(pattern, text, re.S | re.I) is None
]
for forbidden in (
    "legacyPromotionBinaryRemoved\": False",
    "legacyPromotionLoadCommandRemoved\": False",
):
    if forbidden in packager:
        failed.append(forbidden)

if failed:
    print("FAIL: " + ", ".join(failed))
    sys.exit(1)
print("PASS: Build 852 legacy cutoff packaging contract")
