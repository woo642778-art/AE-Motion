#!/usr/bin/env python3
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
coordinator = (ROOT / "Sources/AEMotionUI271Host/AEMotionGlobalShellCoordinator.swift").read_text(encoding="utf-8")
shell = (ROOT / "Sources/AEMotionUI271Host/AEMotionShellViewController.swift").read_text(encoding="utf-8")
installer = (ROOT / "Sources/AEMotionUI271Host/AEMotionUI271Installer.swift").read_text(encoding="utf-8")
release = (ROOT / "Sources/AEMotionExtensionsCore/AEMotionRelease.swift").read_text(encoding="utf-8")
build = (ROOT / "scripts/build-ios-framework.sh").read_text(encoding="utf-8")
launch_path = ROOT / "Sources/AEMotionUI271Host/AEMotionLaunchOverlay.swift"
launch = launch_path.read_text(encoding="utf-8") if launch_path.exists() else ""
packager_path = ROOT / "scripts/package-ui272-build846-ipa.py"
packager = packager_path.read_text(encoding="utf-8") if packager_path.exists() else ""

checks = {
    "dynamic tab lookup": (coordinator, r"func\s+index\(for\s+tab:.*controllerMarkers"),
    "four-tab project fallback": (coordinator, r"count\s*==\s*4.*projects.*2.*templates.*3"),
    "no fixed project index": (coordinator, r"case\s+\.projects:\s*index\s*=\s*3"),
    "settings storyboard restored": (coordinator + shell, r"SettingsNC"),
    "profile storyboard restored": (coordinator + shell, r"MyAccountVC"),
    "settings button": (shell, r"gearshape|settings"),
    "profile button": (shell, r"person\.crop\.circle|profile"),
    "launch overlay installer": (installer, r"AEMotionLaunchOverlay\.install\(\)"),
    "launch readiness signal": (coordinator, r"AEMotionLaunchOverlay\.markShellReady\(\)"),
    "minimum launch duration": (launch, r"minimumVisibleDuration\s*[:=].*1\.[2-9]"),
    "official channel button": (launch, r"Join AE Motion Telegram"),
    "official channel URL": (launch, r"https://t\.me/aemotionios"),
    "Build 846 marker": (launch, r"Build 846"),
    "constructor patch both slices": (packager, r"0x4000.*fd7bbfa9.*7f2303d5.*c0035fd6"),
    "compatibility dylib preserved": (packager, r"blatantsPatch.*preserv"),
    "legacy initializer verification": (packager, r"legacyPromotionInitializerDisabled"),
    "Build 846 release": (release + build + packager, r"buildNumber\s*=\s*846.*CFBundleVersion\": \"846\".*BUILD_NUMBER\s*=\s*846"),
}

failed = []
for name, (text, pattern) in checks.items():
    matched = re.search(pattern, text, re.S | re.I) is not None
    if name == "no fixed project index":
        if matched:
            failed.append(name)
    elif not matched:
        failed.append(name)

for forbidden in (
    "AEMotionLegacyPromotionSuppressor",
    "method_setImplementation",
    "BLATANT_RELATIVE.*unlink",
    "remove_load_dylib.*BLATANT_LOAD_PATH",
):
    if re.search(forbidden, installer + "\n" + launch + "\n" + packager, re.S | re.I):
        failed.append(f"forbidden: {forbidden}")

if failed:
    print("FAIL: " + ", ".join(failed))
    sys.exit(1)
print("PASS: Build 846 device regression contract")
