#!/usr/bin/env python3
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
installer = (ROOT / "Sources/AEMotionUI271Host/AEMotionUI271Installer.swift").read_text(encoding="utf-8")
resolver = (ROOT / "Sources/AEMotionUI271Host/AEMotionRuntimeResolver.swift").read_text(encoding="utf-8")
adapter = (ROOT / "Sources/AEMotionUI271Host/AEMotionHostSurfaceAdapter.swift").read_text(encoding="utf-8")
home = (ROOT / "Sources/AEMotionUI271Host/AEMotionHomeViewController.swift").read_text(encoding="utf-8")
release = (ROOT / "Sources/AEMotionExtensionsCore/AEMotionRelease.swift").read_text(encoding="utf-8")
build = (ROOT / "scripts/build-ios-framework.sh").read_text(encoding="utf-8")
coordinator_path = ROOT / "Sources/AEMotionUI271Host/AEMotionProjectActionCoordinator.swift"
studio_path = ROOT / "Sources/AEMotionUI271Host/AEMotionStudioRouter.swift"
coordinator = coordinator_path.read_text(encoding="utf-8") if coordinator_path.exists() else ""
studio = studio_path.read_text(encoding="utf-8") if studio_path.exists() else ""

checks = {
    "bounded late installer retry": (installer, r"didFinishLaunchingNotification.*didBecomeActiveNotification.*asyncAfter"),
    "idempotent runtime hooks": (resolver, r"installedClasses"),
    "layout refresh hook": (resolver, r"viewDidLayoutSubviews"),
    "non-home legacy branch cleanup": (adapter, r"hasPrefix\(\"aemotion\.home\.\"\).*topLevelBranch"),
    "native tab bar replacement": (adapter, r"tabBar\.isHidden\s*=\s*true"),
    "project editor detection": (coordinator, r"ProjectEditVC"),
    "continue before tool": (coordinator, r"continueEditing.*waitForEditor"),
    "deferred tool execution": (coordinator, r"asyncAfter.*sendActions"),
    "production 3d browser": (studio, r"ThreeDStudioProjectBrowserViewController"),
    "production world browser": (studio, r"WorldStudioProjectBrowserViewController"),
    "proof controller rejected": (studio, r"ThreeDMetalProofViewController"),
    "quick tool precompose": (home, r"Pre-comp"),
    "quick tool tracking": (home, r"Track"),
    "quick tool matte": (home, r"Matte"),
    "quick tool depth": (home, r"Depth"),
    "quick tool text": (home, r"Text"),
    "build 841 release": (release + build, r"buildNumber\s*=\s*841.*CFBundleVersion\": \"841\""),
}

failed = [name for name, (text, pattern) in checks.items() if re.search(pattern, text, re.S) is None]
if failed:
    print("FAIL: " + ", ".join(failed))
    sys.exit(1)
print("PASS: Build 841 device regression contract")
