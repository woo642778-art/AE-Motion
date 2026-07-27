#!/usr/bin/env python3
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
nav = (ROOT / "Sources/AEMotionUI271Host/AEMotionShellNavigationView.swift").read_text(encoding="utf-8")
home = (ROOT / "Sources/AEMotionUI271Host/AEMotionHomeViewController.swift").read_text(encoding="utf-8")
shell = (ROOT / "Sources/AEMotionUI271Host/AEMotionShellViewController.swift").read_text(encoding="utf-8")

checks = {
    "single shell owner": (shell, r'final class AEMotionShellViewController'),
    "navigation owned by shell": (shell, r'AEMotionShellNavigationView'),
    "workspace": (home, r'Workspace'),
    "continue editing": (home, r'Continue editing'),
    "new project": (home, r'New Project'),
    "import": (home, r'Import'),
    "tutorials": (home, r'Tutorials'),
    "templates": (home, r'Templates'),
    "3d studio": (home, r'3D Studio'),
    "world studio": (home, r'Real-Time World Studio'),
    "quick tools": (home, r'Quick tools'),
    "home identifiers": (home, r'aemotion\.home\.'),
    "root tabs": (nav, r'HomeShellTab\.allCases'),
    "create tray": (shell, r'New Project.*Import.*Camera.*Asset Library'),
    "non-root hide": (shell, r'isRootNavigationVisible'),
    "reuse controllers": (shell, r'rootControllers'),
}

failed = [name for name, (content, pattern) in checks.items() if re.search(pattern, content, re.S) is None]
if "AEMotionShellNavigationView" in home:
    failed.append("home content owns global navigation")
combined = home + nav + shell
if re.search(r'fakeProject|placeholderProject|sampleProject', combined, re.I):
    failed.append("fake project data")
if failed:
    print("FAIL: " + ", ".join(failed))
    sys.exit(1)
print("PASS: UI 2.7.1 home shell contract")
