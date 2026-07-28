#!/usr/bin/env python3
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
suppressor = (ROOT / "Sources/AEMotionUI271Host/AEMotionLaunchBrandingSanitizer.swift").read_text(encoding="utf-8")
official = (ROOT / "Sources/AEMotionUI271Host/AEMotionLaunchOverlay.swift").read_text(encoding="utf-8")
container = (ROOT / "Sources/AEMotionUI271Host/AEMotionRootContainerViewController.swift").read_text(encoding="utf-8")
combined = suppressor + "\n" + official + "\n" + container

required = {
    "bounded suppression": r"maximumScans\s*=\s*40.*scanCount\s*<\s*maximumScans",
    "suppression cleanup": r"observers\.forEach\(NotificationCenter\.default\.removeObserver\).*observers\.removeAll",
    "legacy branding fingerprint": r"blatant.*cracked by.*t\.me/blatants",
    "legacy button fingerprint": r"hasLegacyButtonStructure.*telegram.*close|continue",
    "non-normal legacy window": r"window\.windowLevel\s*>\s*\.normal",
    "main window preserved": r"window\.windowLevel\s*==\s*\.normal",
    "official identifier exclusion": r"aemotion\.official-channel\.root",
    "official URL": r"https://t\.me/aemotionios",
    "controller modal": r"modalPresentationStyle\s*=\s*\.overFullScreen",
    "scrollable card": r"UIScrollView.*contentLayoutGuide.*frameLayoutGuide",
    "compact adaptive width": r"safeAreaLayoutGuide\.widthAnchor.*constant:\s*-40",
    "maximum card width": r"widthAnchor\.constraint\(lessThanOrEqualToConstant:\s*430\)",
    "safe area height": r"safeAreaLayoutGuide\.heightAnchor.*constant:\s*-40",
    "join action": r"Join AE Motion Telegram",
    "continue action": r"Continue to AE Motion",
    "root-owned presentation": r"presentOfficialChannelIfNeeded.*AEMotionLaunchOverlay\.presentIfNeeded",
    "create tray excluded": r"!routeState\.isCreateTrayPresented",
}

failed = [name for name, pattern in required.items() if re.search(pattern, combined, re.S | re.I) is None]
for name, pattern in {
    "unmanaged official overlay": r"window\.addSubview\(overlay\)",
    "new startup window": r"UIWindow\s*\(",
    "key-window takeover": r"makeKeyAndVisible|\.makeKey\s*\(",
    "unbounded suppression": r"while\s+true|repeatCount\s*=\s*\.infinity",
    "generic dark view suppression": r"backgroundColor.*black.*isHidden\s*=\s*true",
}.items():
    if re.search(pattern, combined, re.S | re.I):
        failed.append(name)

if failed:
    print("FAIL: " + ", ".join(failed))
    sys.exit(1)
print("PASS: Build 851 promotion contract")
