#!/usr/bin/env python3
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
installer = (ROOT / "Sources/AEMotionUI271Host/AEMotionUI271Installer.swift").read_text(encoding="utf-8")
shell = (ROOT / "Sources/AEMotionUI271Host/AEMotionShellViewController.swift").read_text(encoding="utf-8")
coordinator = (ROOT / "Sources/AEMotionUI271Host/AEMotionGlobalShellCoordinator.swift").read_text(encoding="utf-8")
tutorial = (ROOT / "Sources/AEMotionUI271Host/AEMotionTutorialViewController.swift").read_text(encoding="utf-8")
container_path = ROOT / "Sources/AEMotionUI271Host/AEMotionRootContainerViewController.swift"
container = container_path.read_text(encoding="utf-8") if container_path.exists() else ""
release = (ROOT / "Sources/AEMotionExtensionsCore/AEMotionRelease.swift").read_text(encoding="utf-8")
build = (ROOT / "scripts/build-ios-framework.sh").read_text(encoding="utf-8")

checks = {
    "global shell starts from constructor installer": (installer, r"AEMotionGlobalShellCoordinator\.start\(\)"),
    "window-level root ownership": (coordinator + container, r"window\.rootViewController\s*=\s*container"),
    "native tab bar hidden globally": (coordinator, r"tabBar\.isHidden\s*=\s*true"),
    "root tab routing": (coordinator, r"selectedIndex\s*=\s*index"),
    "editor/detail shell removal": (coordinator + container, r"hideShell\(\)"),
    "AE Motion top header": (shell, r"AEMotionShellHeaderView.*AE Motion"),
    "custom tutorial controller": (shell + tutorial, r"AEMotionTutorialViewController.*Learning Studio"),
    "custom home and tutorial ownership": (shell, r"shouldShowHome.*shouldShowTutorial"),
    "Build 845 identity": (release + build, r"buildNumber\s*=\s*845.*CFBundleVersion\": \"845\""),
}

failed = [name for name, (text, pattern) in checks.items() if re.search(pattern, text, re.S) is None]
if failed:
    print("FAIL: " + ", ".join(failed))
    sys.exit(1)
print("PASS: full-window global shell foundation contract")
