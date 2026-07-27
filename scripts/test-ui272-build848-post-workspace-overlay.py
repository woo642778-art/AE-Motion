#!/usr/bin/env python3
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
launch = (ROOT / "Sources/AEMotionUI271Host/AEMotionLaunchOverlay.swift").read_text(encoding="utf-8")
coordinator = (ROOT / "Sources/AEMotionUI271Host/AEMotionGlobalShellCoordinator.swift").read_text(encoding="utf-8")
release = (ROOT / "Sources/AEMotionExtensionsCore/AEMotionRelease.swift").read_text(encoding="utf-8")
build = (ROOT / "scripts/build-ios-framework.sh").read_text(encoding="utf-8")
packager = (ROOT / "scripts/package-ui272-build848-ipa.py").read_text(encoding="utf-8")

checks = {
    "installer is passive": (launch, r"static func install\(\)\s*\{\s*hasInstalled\s*=\s*true\s*\}"),
    "shell readiness triggers presentation": (coordinator, r"AEMotionLaunchOverlay\.markShellReady\(\)"),
    "existing normal window lookup": (launch, r"preferredExistingApplicationWindow.*windowLevel\s*==\s*\.normal"),
    "overlay added to existing window": (launch, r"window\.addSubview\(overlay\)"),
    "single presentation guard": (launch, r"!isCompleted.*!isPresented.*!isPresentationScheduled"),
    "official channel URL": (launch, r"https://t\.me/aemotionios"),
    "continue action": (launch, r"Continue to AE Motion"),
    "Build 848 dismissal key": (launch, r"aemotion\.build848\.official-channel-dismissed"),
    "Build 848 release": (release + build, r"buildNumber\s*=\s*848.*CFBundleVersion\": \"848\""),
    "Build 848 packaging": (packager, r"BUILD_NUMBER\s*=\s*848.*AE Motion 848"),
    "arm64 promotion repair retained": (packager, r"0x57c0"),
    "arm64e promotion repair retained": (packager, r"0x5910"),
    "first initializer preservation retained": (packager, r"0x4000"),
}

failed = [
    name
    for name, (text, pattern) in checks.items()
    if re.search(pattern, text, re.S | re.I) is None
]

forbidden = {
    "startup UIWindow construction": r"UIWindow\s*\(",
    "key-window takeover": r"makeKeyAndVisible|\.makeKey\s*\(",
    "window-level mutation": r"window\.windowLevel\s*=",
    "launch progress UI": r"UIProgressView|progressTimer|Starting extensions|Preparing Motion Workspace",
    "launch timing gate": r"minimumVisibleDuration|maximumVisibleDuration|didReachMinimumDuration",
    "launch notification observers": r"didFinishLaunchingNotification|didBecomeActiveNotification|UIWindow\.didBecomeVisibleNotification",
}
for name, pattern in forbidden.items():
    if re.search(pattern, launch, re.S | re.I):
        failed.append(name)

if failed:
    print("FAIL: " + ", ".join(failed))
    sys.exit(1)
print("PASS: Build 848 post-workspace overlay contract")
