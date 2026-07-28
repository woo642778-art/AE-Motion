#!/usr/bin/env python3
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
coordinator = (ROOT / "Sources/AEMotionUI271Host/AEMotionGlobalShellCoordinator.swift").read_text(encoding="utf-8")
container = (ROOT / "Sources/AEMotionUI271Host/AEMotionRootContainerViewController.swift").read_text(encoding="utf-8")
combined = coordinator + "\n" + container

required = {
    "single root replacement": r"window\.rootViewController\s*=\s*container",
    "idempotent installation": r"installation\s*!=\s*nil|installedContainer\s*!=\s*nil",
    "bounded attempts": r"maximumInstallationAttempts\s*=\s*(?:[1-9]|[12][0-9]|3[0-2])",
    "observer cleanup": r"removeObserver|observers\.removeAll",
    "host child containment": r"addChild\(hostController\).*hostController\.didMove\(toParent:\s*self\)",
    "shell child containment": r"addChild\(shellController\).*shellController\.didMove\(toParent:\s*self\)",
}

failed = [name for name, pattern in required.items() if re.search(pattern, combined, re.S) is None]
for name, pattern in {
    "unmanaged window shell": r"window\.addSubview\(shell\.view\)",
    "legacy refresh burst": r"scheduleRefreshBurst",
    "120-attempt polling": r"0\.\.<120|attempt\s+in\s+0\.\.<120",
    "post-install polling": r"refreshVisibleShell",
}.items():
    if re.search(pattern, combined):
        failed.append(name)

if failed:
    print("FAIL: " + ", ".join(failed))
    sys.exit(1)
print("PASS: Build 851 root installation contract")
