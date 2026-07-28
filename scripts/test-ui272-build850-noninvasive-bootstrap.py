#!/usr/bin/env python3
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
coordinator = (ROOT / "Sources/AEMotionUI271Host/AEMotionGlobalShellCoordinator.swift").read_text(encoding="utf-8")
san = (ROOT / "Sources/AEMotionUI271Host/AEMotionLaunchBrandingSanitizer.swift").read_text(encoding="utf-8")
release = (ROOT / "Sources/AEMotionExtensionsCore/AEMotionRelease.swift").read_text(encoding="utf-8")
build = (ROOT / "scripts/build-ios-framework.sh").read_text(encoding="utf-8")
packager_path = ROOT / "scripts/package-ui272-build850-ipa.py"
packager = packager_path.read_text(encoding="utf-8") if packager_path.exists() else ""

checks = {
    "Build 850 release": (release + build, r"buildNumber\s*=\s*850.*CFBundleVersion\": \"850\""),
    "stable workspace gate": (coordinator, r"stableCandidateCount.*requiredStableCandidateCount"),
    "exact root marker gate": (coordinator, r"isVerifiedRootController"),
    "visible tab gate": (coordinator, r"tabController\.viewIfLoaded\?\.window\s*===\s*window"),
    "active app gate": (coordinator, r"UIApplication\.shared\.applicationState\s*==\s*\.active"),
    "loading indicator gate": (coordinator, r"containsVisibleActivityIndicator"),
    "window overlay attachment": (coordinator, r"window\.addSubview\(shell\.view\)"),
    "passive text-based branding removal": (san, r"containsLegacyBranding.*window\.isHidden\s*=\s*true"),
    "Build 850 packager": (packager, r"BUILD_NUMBER\s*=\s*850.*AE Motion 850"),
    "UI before host tweak": (packager, r"insert_load_dylib_before.*ALIGHT_MOTION_LOAD_PATH"),
    "promotion code unchanged": (packager, r"PATCHED_PROMOTION_DYLIB_SHA256.*promotionCodeBytesUnchanged"),
}

failed = [name for name, (text, pattern) in checks.items() if re.search(pattern, text, re.S | re.I) is None]

forbidden = {
    "root controller replacement": r"window\.rootViewController\s*=\s*(?!=)",
    "root container installation": r"ensureRootContainer|AEMotionRootContainerViewController\(",
    "launch notification polling": r"UIApplication\.didFinishLaunchingNotification",
    "index fallback before readiness": r"controllers\.count\s*==\s*4|controllers\.count\s*>=\s*5",
    "UIApplication method swizzle": r"method_exchangeImplementations|class_getInstanceMethod",
    "AlightMotion initializer patch": r"PROMOTION_INITIALIZER|PROMOTION_CALLBACK|RETURN_INSTRUCTION",
}
for name, pattern in forbidden.items():
    if re.search(pattern, coordinator + "\n" + san + "\n" + packager, re.S | re.I):
        failed.append(name)

if failed:
    print("FAIL: " + ", ".join(failed))
    sys.exit(1)
print("PASS: Build 850 non-invasive bootstrap contract")
