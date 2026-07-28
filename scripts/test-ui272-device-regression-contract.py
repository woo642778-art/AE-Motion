#!/usr/bin/env python3
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
installer = (ROOT / "Sources/AEMotionUI271Host/AEMotionUI271Installer.swift").read_text(encoding="utf-8")
coordinator = (ROOT / "Sources/AEMotionUI271Host/AEMotionGlobalShellCoordinator.swift").read_text(encoding="utf-8")
container = (ROOT / "Sources/AEMotionUI271Host/AEMotionRootContainerViewController.swift").read_text(encoding="utf-8")
home = (ROOT / "Sources/AEMotionUI271Host/AEMotionHomeViewController.swift").read_text(encoding="utf-8")
shell = (ROOT / "Sources/AEMotionUI271Host/AEMotionShellViewController.swift").read_text(encoding="utf-8")
route = (ROOT / "Sources/AEMotionExtensionsCore/AEMotionRouteState.swift").read_text(encoding="utf-8")
release = (ROOT / "Sources/AEMotionExtensionsCore/AEMotionRelease.swift").read_text(encoding="utf-8")
build = (ROOT / "scripts/build-ios-framework.sh").read_text(encoding="utf-8")
actions = (ROOT / "Sources/AEMotionUI271Host/AEMotionActionRouter.swift").read_text(encoding="utf-8")
studio = (ROOT / "Sources/AEMotionUI271Host/AEMotionStudioRouter.swift").read_text(encoding="utf-8")
modal = (ROOT / "Sources/AEMotionUI271Host/AEMotionModalPresentationCoordinator.swift").read_text(encoding="utf-8")
promotion = (ROOT / "Sources/AEMotionUI271Host/AEMotionLaunchBrandingSanitizer.swift").read_text(encoding="utf-8")
official = (ROOT / "Sources/AEMotionUI271Host/AEMotionLaunchOverlay.swift").read_text(encoding="utf-8")

checks = {
    "global installer": (installer, r"AEMotionGlobalShellCoordinator\.start\(\)"),
    "bounded installation": (coordinator, r"maximumInstallationAttempts\s*=\s*32"),
    "single root replacement": (coordinator, r"window\.rootViewController\s*=\s*container"),
    "root tab discovery": (coordinator, r"findTabController"),
    "root containment": (container, r"addChild\(hostController\).*addChild\(shellController\)"),
    "single route state": (route + container, r"AEMotionRouteState.*private\(set\) var routeState"),
    "create tray toggle": (route, r"toggleCreateTray"),
    "create tray dismissal": (route, r"dismissCreateTray"),
    "settings restoration": (modal + shell, r"SettingsNC.*gearshape"),
    "account restoration": (modal + shell, r"MyAccountVC.*person\.crop\.circle"),
    "explicit modal close": (modal, r"barButtonSystemItem:\s*\.close"),
    "production 3d browser": (studio, r"ThreeDStudioProjectBrowserViewController"),
    "production world browser": (studio, r"WorldStudioProjectBrowserViewController"),
    "studio close": (studio, r"barButtonSystemItem:\s*\.close"),
    "active editor detection": (actions, r"ProjectEditVC"),
    "visible control guard": (actions, r"isVisibleAndInteractive"),
    "quick tool precompose": (home, r"Pre-comp"),
    "quick tool tracking": (home, r"Track"),
    "quick tool matte": (home, r"Matte"),
    "quick tool depth": (home, r"Depth"),
    "quick tool text": (home, r"Text"),
    "bounded promotion suppression": (promotion, r"maximumScans\s*=\s*40.*stop\(\)"),
    "official URL": (official, r"https://t\.me/aemotionios"),
    "controller modal official card": (official, r"modalPresentationStyle\s*=\s*\.overFullScreen"),
    "adaptive card width": (official, r"safeAreaLayoutGuide\.widthAnchor.*constant:\s*-40"),
    "Build 852 release": (release + build, r"buildNumber\s*=\s*852.*CFBundleVersion\": \"852\""),
}

failed = [
    name
    for name, (text, pattern) in checks.items()
    if re.search(pattern, text, re.S | re.I) is None
]
combined = coordinator + container + shell + actions + promotion + official
for name, pattern in {
    "unmanaged window shell": r"window\.addSubview\(shell\.view\)",
    "refresh burst": r"scheduleRefreshBurst",
    "120-attempt polling": r"0\.\.<120",
    "official window overlay": r"window\.addSubview\(overlay\)",
    "optimistic openNonRoot": r"openNonRoot\(",
}.items():
    if re.search(pattern, combined):
        failed.append(name)
if failed:
    print("FAIL: " + ", ".join(failed))
    sys.exit(1)
print("PASS: Build 852 device regression contract")
