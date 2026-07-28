#!/usr/bin/env python3
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
router = (ROOT / "Sources/AEMotionUI271Host/AEMotionActionRouter.swift").read_text(encoding="utf-8")
result = (ROOT / "Sources/AEMotionUI271Host/AEMotionActionResult.swift").read_text(encoding="utf-8")
studio = (ROOT / "Sources/AEMotionUI271Host/AEMotionStudioRouter.swift").read_text(encoding="utf-8")
container = (ROOT / "Sources/AEMotionUI271Host/AEMotionRootContainerViewController.swift").read_text(encoding="utf-8")
combined = router + result + studio + container

required = {
    "explicit opened result": r"case opened\(AEMotionNonRootRoute\)",
    "open project result": r"case requiresOpenProject",
    "unavailable result": r"case unavailable\(String\)",
    "failed result": r"case failed\(String\)",
    "visible control requirement": r"isVisibleAndInteractive",
    "window attachment requirement": r"control\.window\s*!=\s*nil",
    "enabled requirement": r"control\.isEnabled",
    "destination verification": r"changedController\s*\|\|\s*editorOpened",
    "active editor check": r"ProjectEditVC",
    "3D production controller": r"ThreeDStudioProjectBrowserViewController",
    "World production controller": r"WorldStudioProjectBrowserViewController",
    "explicit studio close": r"barButtonSystemItem:\s*\.close",
    "state after result": r"handleActionResult.*confirmNonRoot",
}

failed = [name for name, pattern in required.items() if re.search(pattern, combined, re.S) is None]
if re.search(r"completion\(\.opened.*\).*sendActions", router, re.S):
    failed.append("optimistic success before action verification")
if "controls: [AEMotionHomeAction: UIControl]" in router:
    failed.append("legacy hidden-control map")
if failed:
    print("FAIL: " + ", ".join(failed))
    sys.exit(1)
print("PASS: Build 851 action routing contract")
