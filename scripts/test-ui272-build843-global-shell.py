#!/usr/bin/env python3
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
installer = (ROOT / "Sources/AEMotionUI271Host/AEMotionUI271Installer.swift").read_text(encoding="utf-8")
shell = (ROOT / "Sources/AEMotionUI271Host/AEMotionShellViewController.swift").read_text(encoding="utf-8")
coordinator_path = ROOT / "Sources/AEMotionUI271Host/AEMotionGlobalShellCoordinator.swift"
tutorial_path = ROOT / "Sources/AEMotionUI271Host/AEMotionTutorialViewController.swift"
coordinator = coordinator_path.read_text(encoding="utf-8") if coordinator_path.exists() else ""
tutorial = tutorial_path.read_text(encoding="utf-8") if tutorial_path.exists() else ""
macho = (ROOT / "scripts/macho_load_command.py").read_text(encoding="utf-8")
packager = (
    (ROOT / "scripts/package-ui272-ipa.py").read_text(encoding="utf-8")
    + "\n"
    + (ROOT / "scripts/package-ui272-build843-ipa.py").read_text(encoding="utf-8")
)
release = (ROOT / "Sources/AEMotionExtensionsCore/AEMotionRelease.swift").read_text(encoding="utf-8")
build = (ROOT / "scripts/build-ios-framework.sh").read_text(encoding="utf-8")

checks = {
    "global shell starts from constructor installer": (installer, r"AEMotionGlobalShellCoordinator\.start\(\)"),
    "window-level root ownership": (coordinator, r"window\.rootViewController.*AEMotionShellViewController\.shared"),
    "native tab bar hidden globally": (coordinator, r"tabBar\.isHidden\s*=\s*true"),
    "root tab routing": (coordinator, r"selectedIndex.*HomeShellTab"),
    "editor/detail shell removal": (coordinator, r"detachFromCurrentHost"),
    "AE Motion top header": (shell, r"AEMotionShellHeaderView.*AE Motion"),
    "custom tutorial controller": (shell + tutorial, r"AEMotionTutorialViewController.*Learning Studio"),
    "custom home and tutorial ownership": (shell, r"shouldShowHome.*shouldShowTutorial"),
    "Mach-O dylib removal primitive": (macho, r"def remove_load_dylib\("),
    "Blatant load command removed": (packager, r"remove_load_dylib\(.*BLATANT_LOAD_PATH"),
    "Blatant file deleted": (packager, r"BLATANT_RELATIVE.*unlink\("),
    "Build 843 identity": (release + build + packager, r"buildNumber\s*=\s*843.*CFBundleVersion\": \"843\".*BUILD_NUMBER\s*=\s*843"),
}

failed = [name for name, (text, pattern) in checks.items() if re.search(pattern, text, re.S) is None]
if failed:
    print("FAIL: " + ", ".join(failed))
    sys.exit(1)
print("PASS: Build 843 global shell and Blatant removal contract")
