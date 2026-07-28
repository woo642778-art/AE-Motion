#!/usr/bin/env python3
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
modal = (ROOT / "Sources/AEMotionUI271Host/AEMotionModalPresentationCoordinator.swift").read_text(encoding="utf-8")
container = (ROOT / "Sources/AEMotionUI271Host/AEMotionRootContainerViewController.swift").read_text(encoding="utf-8")
route = (ROOT / "Sources/AEMotionExtensionsCore/AEMotionRouteState.swift").read_text(encoding="utf-8")
combined = modal + container + route

required = {
    "settings storyboard": r"SettingsNC",
    "account storyboard": r"MyAccountVC",
    "navigation wrapper": r"UINavigationController",
    "explicit close": r"barButtonSystemItem:\s*\.close",
    "single active route": r"activeRoute\s*==\s*nil",
    "presentation delegate": r"UIAdaptivePresentationControllerDelegate",
    "dismiss callback once": r"didReportDismissal",
    "settings route state": r"presentModal\(\.settings\)",
    "account route state": r"presentModal\(\.account\)",
    "dismiss route state": r"event:\s*\.dismissModal",
}

failed = [name for name, pattern in required.items() if re.search(pattern, combined, re.S) is None]
if re.search(r"presentStoryboard\(named:", container):
    failed.append("legacy direct modal presentation")
if failed:
    print("FAIL: " + ", ".join(failed))
    sys.exit(1)
print("PASS: Build 851 modal routing contract")
