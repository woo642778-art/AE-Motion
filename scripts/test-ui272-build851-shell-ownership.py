#!/usr/bin/env python3
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
container = (ROOT / "Sources/AEMotionUI271Host/AEMotionRootContainerViewController.swift").read_text(encoding="utf-8")
shell = (ROOT / "Sources/AEMotionUI271Host/AEMotionShellViewController.swift").read_text(encoding="utf-8")
content = (ROOT / "Sources/AEMotionUI271Host/AEMotionShellContentController.swift").read_text(encoding="utf-8")
tray = (ROOT / "Sources/AEMotionUI271Host/AEMotionCreateTrayController.swift").read_text(encoding="utf-8")
route = (ROOT / "Sources/AEMotionExtensionsCore/AEMotionRouteState.swift").read_text(encoding="utf-8")
combined = container + shell + content + tray + route

required = {
    "root route owner": r"private\(set\) var routeState: AEMotionRouteState",
    "host child containment": r"addChild\(hostController\).*hostController\.didMove",
    "shell child containment": r"addChild\(shellController\).*shellController\.didMove",
    "source home": r"AEMotionHomeViewController",
    "source tutorials": r"AEMotionTutorialViewController",
    "host content passthrough": r"passesHostContentTouches",
    "tray center toggle": r"onToggleCreate",
    "tray outside dismiss": r"dismiss-region.*onDismiss",
    "tray tab dismissal": r"selectTab.*isCreateTrayPresented\s*=\s*false",
    "tray background dismissal": r"applicationDidEnterBackground",
    "hidden interaction disabled": r"isUserInteractionEnabled\s*=\s*false",
}

failed = [name for name, pattern in required.items() if re.search(pattern, combined, re.S) is None]
for name, pattern in {
    "unmanaged shell attachment": r"window\.addSubview\(shell\.view\)",
    "shell-owned route state": r"private\(set\) var state = HomeShellState",
    "hardcoded Build 846": r"Build 846",
    "hardcoded Build 850": r"Build 850",
}.items():
    if re.search(pattern, combined):
        failed.append(name)

if failed:
    print("FAIL: " + ", ".join(failed))
    sys.exit(1)
print("PASS: Build 851 shell ownership contract")
