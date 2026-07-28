#!/usr/bin/env python3
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
nav = (ROOT / "Sources/AEMotionUI271Host/AEMotionShellNavigationView.swift").read_text(encoding="utf-8")
home = (ROOT / "Sources/AEMotionUI271Host/AEMotionHomeViewController.swift").read_text(encoding="utf-8")
shell = (ROOT / "Sources/AEMotionUI271Host/AEMotionShellViewController.swift").read_text(encoding="utf-8")
content = (ROOT / "Sources/AEMotionUI271Host/AEMotionShellContentController.swift").read_text(encoding="utf-8")
tray = (ROOT / "Sources/AEMotionUI271Host/AEMotionCreateTrayController.swift").read_text(encoding="utf-8")
route = (ROOT / "Sources/AEMotionExtensionsCore/AEMotionRouteState.swift").read_text(encoding="utf-8")
release = (ROOT / "Sources/AEMotionExtensionsCore/AEMotionRelease.swift").read_text(encoding="utf-8")

checks = {
    "single shell owner": (shell, r"final class AEMotionShellViewController"),
    "typed root navigation": (nav, r"AEMotionRootTab"),
    "route state": (route, r"struct AEMotionRouteState"),
    "create toggle event": (route, r"toggleCreateTray"),
    "outside dismiss event": (route, r"dismissCreateTray"),
    "source home controller": (content, r"AEMotionHomeViewController"),
    "source tutorial controller": (content, r"AEMotionTutorialViewController"),
    "workspace": (home, r"Workspace"),
    "continue editing": (home, r"Continue editing"),
    "3d studio": (home, r"3D Studio"),
    "world studio": (home, r"Real-Time World Studio"),
    "quick tools": (home, r"Quick tools"),
    "create actions": (tray, r"New Project.*Import.*Camera.*Asset Library"),
    "outside tap control": (tray, r"dismiss-region.*onDismiss"),
    "dynamic build metadata": (shell, r"AEMotionRelease\.buildNumber"),
    "Build 852 release": (release, r"buildNumber\s*=\s*852"),
}

failed = [name for name, (content, pattern) in checks.items() if re.search(pattern, content, re.S) is None]
combined = nav + home + shell + content + tray
for stale in ("Build 846", "Build 848", "Build 849", "Build 850", "Build 851"):
    if stale in combined:
        failed.append(f"stale literal: {stale}")
if re.search(r"fakeProject|placeholderProject|sampleProject", combined, re.I):
    failed.append("fake project data")
if failed:
    print("FAIL: " + ", ".join(failed))
    sys.exit(1)
print("PASS: Build 852 home shell contract")
