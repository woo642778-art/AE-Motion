#!/usr/bin/env python3
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
installer = (ROOT / "Sources/AEMotionUI271Host/AEMotionUI271Installer.swift").read_text(encoding="utf-8")
resolver = (ROOT / "Sources/AEMotionUI271Host/AEMotionRuntimeResolver.swift").read_text(encoding="utf-8")
release = (ROOT / "Sources/AEMotionExtensionsCore/AEMotionRelease.swift").read_text(encoding="utf-8")
build = (ROOT / "scripts/build-ios-framework.sh").read_text(encoding="utf-8")
branding_path = ROOT / "Sources/AEMotionUI271Host/AEMotionLaunchBrandingSanitizer.swift"
branding = branding_path.read_text(encoding="utf-8") if branding_path.exists() else ""

checks = {
    "actual template list controller": (installer + resolver, r"TemplatesListVC"),
    "actual template showcase controller": (installer + resolver, r"TemplatesShowcaseVC"),
    "no all-or-nothing host readiness gate": (installer, r"AEMotionRuntimeResolver\.install\(\)"),
    "persistent installed class state": (resolver, r"private\s+static\s+var\s+installedClasses\s*=\s*Set<ObjectIdentifier>"),
    "class-local original alias": (resolver, r"class_addMethod\(\s*cls,\s*replacementSelector,\s*originalIMP"),
    "replace original with wrapper": (resolver, r"class_replaceMethod\(\s*cls,\s*originalSelector,\s*replacementIMP"),
    "immediate visible root refresh": (resolver, r"refreshVisibleRootSurfaces"),
    "branding sanitizer install": (installer, r"AEMotionLaunchBrandingSanitizer\.install\(\)"),
    "official channel URL": (branding, r"https://t\.me/aemotionios"),
    "old telegram URL interception": (branding, r"redirectedTelegramURL"),
    "launch label replacement": (branding, r"Cracked By|Blatant"),
    "telegram button replacement": (branding, r"Join AE Motion Telegram"),
    "build 842 release": (release + build, r"buildNumber\s*=\s*842.*CFBundleVersion\": \"842\""),
}

failed = [name for name, (text, pattern) in checks.items() if re.search(pattern, text, re.S) is None]
if "hostClassesAreReady()" in installer:
    failed.append("obsolete all-or-nothing readiness call")
if "method_exchangeImplementations" in resolver:
    failed.append("shared replacement implementation exchange")
if failed:
    print("FAIL: " + ", ".join(failed))
    sys.exit(1)
print("PASS: Build 842 runtime activation and Telegram branding contract")
