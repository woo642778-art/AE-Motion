#!/usr/bin/env python3
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
resolver = (ROOT / "Sources/AEMotionUI271Host/AEMotionRuntimeResolver.swift").read_text(encoding="utf-8")
adapter = (ROOT / "Sources/AEMotionUI271Host/AEMotionHostSurfaceAdapter.swift").read_text(encoding="utf-8")
installer = (ROOT / "Sources/AEMotionUI271Host/AEMotionUI271Installer.swift").read_text(encoding="utf-8")

checks = {
    "home allowlist": (resolver, r'AlightMotion\.HomeVC.*AlightMotion\.HomeViewVC'),
    "projects allowlist": (resolver, r'AlightMotion\.ProjectsVC'),
    "templates allowlist": (resolver, r'AlightMotion\.TemplatesVC'),
    "associated ownership": (resolver, r'objc_(get|set)AssociatedObject'),
    "exact runtime lookup": (resolver, r'NSClassFromString'),
    "legacy action forwarding": (adapter, r'sendActions\(for:\s*\.touchUpInside\)'),
    "known identifier capture": (adapter, r'aemotion\.home\.'),
    "owned overlay cleanup": (adapter, r'hasPrefix\("aemotion\."\)'),
    "contrast normalization": (adapter, r'normalizeTextContrast'),
    "shell root attach": (resolver, r'shell\.attach\(to:'),
    "nonroot hide": (resolver, r'openNonRoot'),
    "legacy before runtime": (installer, r'loadLegacyFramework\(\).*installRuntimeHooks'),
}

failed = [name for name, (content, pattern) in checks.items() if re.search(pattern, content, re.S) is None]
if "objc_getClassList" in resolver:
    failed.append("broad runtime class enumeration")
if "UITableViewDataSource" in adapter or "UICollectionViewDataSource" in adapter:
    failed.append("host data-source replacement")
if failed:
    print("FAIL: " + ", ".join(failed))
    sys.exit(1)
print("PASS: UI 2.7.1 runtime contract")
