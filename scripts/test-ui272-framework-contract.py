#!/usr/bin/env python3
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[1]
package = (root / "Package.swift").read_text(encoding="utf-8")
bootstrap = (root / "Sources/AEMotionUI271Bootstrap/AEMotionUI271Bootstrap.c").read_text(encoding="utf-8")
build_script = (root / "scripts/build-ios-framework.sh").read_text(encoding="utf-8")
combined = package + "\n" + bootstrap + "\n" + build_script

failed: list[str] = []
checks = {
    "dynamic product": 'name: "AEMotionUI272"',
    "installer symbol": "AEMotionUI272Install",
    "constructor bootstrap": "__attribute__((constructor))",
    "framework bundle": "AEMotionUI272.framework",
    "framework executable": 'CFBundleExecutable": "AEMotionUI272"',
    "release version": 'CFBundleShortVersionString": "2.7.2"',
    "release build": 'CFBundleVersion": "852"',
    "install name": "@rpath/AEMotionUI272.framework/AEMotionUI272",
}
for name, token in checks.items():
    if token not in combined:
        failed.append(name)
for forbidden in (
    'name: "AEMotionExtensionsHost",\n            type: .dynamic',
    "AEMotionLegacy",
    "LegacyFrameworkLoader",
):
    if forbidden in combined:
        failed.append(f"forbidden token: {forbidden}")

if failed:
    print("FAIL: " + ", ".join(failed))
    sys.exit(1)
print("PASS: Build 852 separately signable framework contract")
