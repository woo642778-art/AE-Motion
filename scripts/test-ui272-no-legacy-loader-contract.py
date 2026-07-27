#!/usr/bin/env python3
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[1]
package = (root / "Package.swift").read_text(encoding="utf-8")
installer = (root / "Sources/AEMotionUI271Host/AEMotionUI271Installer.swift").read_text(encoding="utf-8")
release = (root / "Sources/AEMotionExtensionsCore/AEMotionRelease.swift").read_text(encoding="utf-8")
combined = package + "\n" + installer

failed: list[str] = []
for forbidden in ("AEMotionLegacy", "LegacyFrameworkLoader", "dlopen", "RTLD_GLOBAL"):
    if forbidden in combined:
        failed.append(f"forbidden legacy loader token: {forbidden}")
if 'marketingVersion = "2.7.2"' not in release:
    failed.append("release version is not 2.7.2")
if "buildNumber = 843" not in release:
    failed.append("release build is not 843")
if 'AEMotionUI272Install' not in installer:
    failed.append("2.7.2 installer symbol is missing")

if failed:
    print("FAIL: " + ", ".join(failed))
    sys.exit(1)
print("PASS: no unsafe legacy wrapper loader")
