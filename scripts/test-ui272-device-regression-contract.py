#!/usr/bin/env python3
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
installer = (ROOT / "Sources/AEMotionUI271Host/AEMotionUI271Installer.swift").read_text(encoding="utf-8")
coordinator = (ROOT / "Sources/AEMotionUI271Host/AEMotionGlobalShellCoordinator.swift").read_text(encoding="utf-8")
adapter = (ROOT / "Sources/AEMotionUI271Host/AEMotionHostSurfaceAdapter.swift").read_text(encoding="utf-8")
home = (ROOT / "Sources/AEMotionUI271Host/AEMotionHomeViewController.swift").read_text(encoding="utf-8")
shell = (ROOT / "Sources/AEMotionUI271Host/AEMotionShellViewController.swift").read_text(encoding="utf-8")
release = (ROOT / "Sources/AEMotionExtensionsCore/AEMotionRelease.swift").read_text(encoding="utf-8")
build = (ROOT / "scripts/build-ios-framework.sh").read_text(encoding="utf-8")
actions = (ROOT / "Sources/AEMotionUI271Host/AEMotionProjectActionCoordinator.swift").read_text(encoding="utf-8")
studio = (ROOT / "Sources/AEMotionUI271Host/AEMotionStudioRouter.swift").read_text(encoding="utf-8")

checks = {
    "global installer": (installer, r"AEMotionGlobalShellCoordinator\.start\(\)"),
    "post-workspace overlay installer": (installer, r"AEMotionLaunchOverlay\.install\(\)"),
    "shell readiness trigger": (coordinator, r"AEMotionLaunchOverlay\.markShellReady\(\)"),
    "bounded global refresh": (coordinator, r"scheduleRefreshBurst.*0\.15"),
    "root tab discovery": (coordinator, r"findTabController"),
    "dynamic project tab": (coordinator, r"controllerMarkers.*projectslistvc.*index\(for"),
    "native tab bar replacement": (coordinator, r"tabBar\.isHidden\s*=\s*true"),
    "stable host readiness": (coordinator, r"requiredStableCandidateCount.*isHostWorkspaceReady"),
    "non-invasive window overlay": (coordinator, r"window\.addSubview\(shell\.view\)"),
    "settings restoration": (coordinator + shell, r"SettingsNC.*gearshape"),
    "profile restoration": (coordinator + shell, r"MyAccountVC.*person\.crop\.circle"),
    "top and bottom chrome ownership": (shell, r"AEMotionShellHeaderView.*bottomChromeView"),
    "bounded root refresh": (adapter, r"scheduleRefresh.*remaining"),
    "non-home legacy branch cleanup": (adapter, r"hasPrefix\(\"aemotion\.home\.\"\).*aemotionTopLevelBranch"),
    "project editor detection": (actions, r"ProjectEditVC"),
    "continue before tool": (actions, r"continueEditing.*waitForEditor"),
    "deferred tool execution": (actions, r"asyncAfter.*sendActions"),
    "production 3d browser": (studio, r"ThreeDStudioProjectBrowserViewController"),
    "production world browser": (studio, r"WorldStudioProjectBrowserViewController"),
    "proof controller rejected": (studio, r"ThreeDMetalProofViewController"),
    "quick tool precompose": (home, r"Pre-comp"),
    "quick tool tracking": (home, r"Track"),
    "quick tool matte": (home, r"Matte"),
    "quick tool depth": (home, r"Depth"),
    "quick tool text": (home, r"Text"),
    "build 850 release": (release + build, r"buildNumber\s*=\s*850.*CFBundleVersion\": \"850\""),
}

failed = [name for name, (text, pattern) in checks.items() if re.search(pattern, text, re.S | re.I) is None]
if re.search(r"window\.rootViewController\s*=", coordinator):
    failed.append("root controller replacement remains")
if failed:
    print("FAIL: " + ", ".join(failed))
    sys.exit(1)
print("PASS: Build 850 device regression contract")
