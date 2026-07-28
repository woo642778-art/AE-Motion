#!/usr/bin/env python3
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
coordinator = (ROOT / "Sources/AEMotionUI271Host/AEMotionGlobalShellCoordinator.swift").read_text(encoding="utf-8")
container = (ROOT / "Sources/AEMotionUI271Host/AEMotionRootContainerViewController.swift").read_text(encoding="utf-8")
action_router = (ROOT / "Sources/AEMotionUI271Host/AEMotionActionRouter.swift").read_text(encoding="utf-8")
modal = (ROOT / "Sources/AEMotionUI271Host/AEMotionModalPresentationCoordinator.swift").read_text(encoding="utf-8")
installer = (ROOT / "Sources/AEMotionUI271Host/AEMotionUI271Installer.swift").read_text(encoding="utf-8")
shell = (ROOT / "Sources/AEMotionUI271Host/AEMotionShellViewController.swift").read_text(encoding="utf-8")
combined = coordinator + container + action_router + modal + installer + shell

checks = {
    "global installer": (installer, r"AEMotionGlobalShellCoordinator\.start"),
    "bounded readiness": (coordinator, r"maximumInstallationAttempts\s*=\s*32"),
    "single root replacement": (coordinator, r"window\.rootViewController\s*=\s*container"),
    "observer cleanup": (coordinator, r"observers\.removeAll"),
    "host containment": (container, r"addChild\(hostController\).*didMove\(toParent:\s*self\)"),
    "shell containment": (container, r"addChild\(shellController\).*didMove\(toParent:\s*self\)"),
    "single route owner": (container, r"private\(set\) var routeState: AEMotionRouteState"),
    "typed action result": (action_router, r"AEMotionActionResult"),
    "visible-control verification": (action_router, r"isVisibleAndInteractive"),
    "settings modal": (modal, r"SettingsNC"),
    "account modal": (modal, r"MyAccountVC"),
    "explicit close": (modal, r"barButtonSystemItem:\s*\.close"),
    "host content passthrough": (shell, r"passesHostContentTouches"),
}

failed = [name for name, (content, pattern) in checks.items() if re.search(pattern, content, re.S) is None]
for name, pattern in {
    "unmanaged window shell": r"window\.addSubview\(shell\.view\)",
    "refresh burst": r"scheduleRefreshBurst",
    "120-attempt loop": r"0\.\.<120",
    "optimistic shell route": r"openNonRoot\(",
}.items():
    if re.search(pattern, combined):
        failed.append(name)
for forbidden in ("LegacyFrameworkLoader", "AEMotionLegacy.framework", "dlopen(", "RTLD_GLOBAL"):
    if forbidden in installer:
        failed.append(f"forbidden installer token: {forbidden}")
if failed:
    print("FAIL: " + ", ".join(failed))
    sys.exit(1)
print("PASS: Build 851 controller-owned runtime contract")
