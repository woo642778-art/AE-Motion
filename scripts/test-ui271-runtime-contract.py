#!/usr/bin/env python3
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
coordinator = (ROOT / "Sources/AEMotionUI271Host/AEMotionGlobalShellCoordinator.swift").read_text(encoding="utf-8")
adapter = (ROOT / "Sources/AEMotionUI271Host/AEMotionHostSurfaceAdapter.swift").read_text(encoding="utf-8")
coordinator_actions = (ROOT / "Sources/AEMotionUI271Host/AEMotionProjectActionCoordinator.swift").read_text(encoding="utf-8")
installer = (ROOT / "Sources/AEMotionUI271Host/AEMotionUI271Installer.swift").read_text(encoding="utf-8")
shell = (ROOT / "Sources/AEMotionUI271Host/AEMotionShellViewController.swift").read_text(encoding="utf-8")

checks = {
    "global shell installer": (installer, r"AEMotionGlobalShellCoordinator\.start"),
    "non-invasive window overlay": (coordinator, r"window\.addSubview\(shell\.view\)"),
    "stable workspace readiness": (coordinator, r"isHostWorkspaceReady.*requiredStableCandidateCount"),
    "tab controller discovery": (coordinator, r"findTabController"),
    "native tab hidden": (coordinator, r"tabBar\.isHidden\s*=\s*true"),
    "legacy action forwarding": (coordinator_actions, r"sendActions\(for:\s*\.touchUpInside\)"),
    "known identifier capture": (adapter, r"aemotion\.home\."),
    "owned overlay cleanup": (adapter, r"hasPrefix\(\"aemotion\.home\.\"\)"),
    "contrast normalization": (adapter, r"normalizeTextContrast"),
    "nonroot shell hiding": (coordinator, r"hideShell\(\)"),
    "AE Motion header": (shell, r"AEMotionShellHeaderView.*AE Motion"),
}

failed = [name for name, (content, pattern) in checks.items() if re.search(pattern, content, re.S) is None]
if re.search(r"window\.rootViewController\s*=\s*(?!=)", coordinator):
    failed.append("host root replacement")
if "objc_getClassList" in coordinator:
    failed.append("broad runtime class enumeration")
if "UITableViewDataSource" in adapter or "UICollectionViewDataSource" in adapter:
    failed.append("host data-source replacement")
for forbidden in ("LegacyFrameworkLoader", "AEMotionLegacy.framework", "dlopen(", "RTLD_GLOBAL"):
    if forbidden in installer:
        failed.append(f"forbidden installer token: {forbidden}")
if failed:
    print("FAIL: " + ", ".join(failed))
    sys.exit(1)
print("PASS: UI 2.7.2 non-invasive full-window runtime contract")
