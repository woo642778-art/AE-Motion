#!/usr/bin/env python3
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
installer = (ROOT / "Sources/AEMotionUI271Host/AEMotionUI271Installer.swift").read_text(encoding="utf-8")
coordinator = (ROOT / "Sources/AEMotionUI271Host/AEMotionGlobalShellCoordinator.swift").read_text(encoding="utf-8")
shell = (ROOT / "Sources/AEMotionUI271Host/AEMotionShellViewController.swift").read_text(encoding="utf-8")
release = (ROOT / "Sources/AEMotionExtensionsCore/AEMotionRelease.swift").read_text(encoding="utf-8")
build = (ROOT / "scripts/build-ios-framework.sh").read_text(encoding="utf-8")
packager_path = ROOT / "scripts/package-ui272-build845-ipa.py"
packager = packager_path.read_text(encoding="utf-8") if packager_path.exists() else ""
suppressor_path = ROOT / "Sources/AEMotionUI271Host/AEMotionLegacyPromotionSuppressor.swift"
suppressor = suppressor_path.read_text(encoding="utf-8") if suppressor_path.exists() else ""

checks = {
    "unsafe runtime promotion hook removed": (
        installer + "\n" + suppressor,
        r"AEMotionLegacyPromotionSuppressor\.install\(\)|method_setImplementation|class_replaceMethod",
        False,
    ),
    "root wrapping waits for presented controllers": (
        coordinator,
        r"presentedViewController\s*==\s*nil|presentedViewController\s*!=\s*nil.*return",
        True,
    ),
    "Build 845 packager exists": (packager, r"BUILD_NUMBER\s*=\s*845", True),
    "Blatant dylib file removed": (packager, r"BLATANT_RELATIVE.*unlink\(", True),
    "Blatant load command removed": (packager, r"remove_load_dylib\(.*BLATANT_LOAD_PATH", True),
    "output rejects Blatant token": (packager, r"legacy branding token remains|blatant token remains|Blatant", True),
    "visible Build 845 marker": (shell, r"Build 845", True),
    "Build 845 release identity": (
        release + "\n" + build,
        r"buildNumber\s*=\s*845.*CFBundleVersion\": \"845\"",
        True,
    ),
}

failed: list[str] = []
for name, (text, pattern, should_match) in checks.items():
    matched = re.search(pattern, text, re.S | re.I) is not None
    if matched != should_match:
        failed.append(name)

if failed:
    print("FAIL: " + ", ".join(failed))
    sys.exit(1)
print("PASS: Build 845 crash recovery contract")
