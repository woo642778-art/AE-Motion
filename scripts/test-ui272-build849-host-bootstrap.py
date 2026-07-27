#!/usr/bin/env python3
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
release = (ROOT / "Sources/AEMotionExtensionsCore/AEMotionRelease.swift").read_text(encoding="utf-8")
build = (ROOT / "scripts/build-ios-framework.sh").read_text(encoding="utf-8")
launch = (ROOT / "Sources/AEMotionUI271Host/AEMotionLaunchOverlay.swift").read_text(encoding="utf-8")
coordinator = (ROOT / "Sources/AEMotionUI271Host/AEMotionGlobalShellCoordinator.swift").read_text(encoding="utf-8")
packager_path = ROOT / "scripts/package-ui272-build849-ipa.py"
packager = packager_path.read_text(encoding="utf-8") if packager_path.exists() else ""

checks = {
    "Build 849 release": (release + build, r"buildNumber\s*=\s*849.*CFBundleVersion\": \"849\""),
    "Build 849 packager": (packager, r"BUILD_NUMBER\s*=\s*849.*AE Motion 849"),
    "arm64 visual callback offset": (packager, r"ARM64_PROMOTION_CALLBACK\s*=\s*0x599C"),
    "arm64e visual callback offset": (packager, r"ARM64E_PROMOTION_CALLBACK\s*=\s*0x5B14"),
    "callback original instruction": (packager, r"PROMOTION_CALLBACK_EXPECTED\s*=\s*bytes\.fromhex\(\"000700f0\"\)"),
    "callback return instruction": (packager, r"RETURN_INSTRUCTION\s*=\s*bytes\.fromhex\(\"c0035fd6\"\)"),
    "all initializers preserved": (packager, r"INITIALIZER_OFFSETS.*0x4000.*0x57C0.*hostInitializersPreserved"),
    "legacy tweak load constant": (packager, r"LEGACY_TWEAK_LOAD_PATH\s*=\s*\"@rpath/AlightMotion\.dylib\""),
    "compatibility load constant": (packager, r"BLATANT_LOAD_PATH\s*=\s*\"@rpath/blatantsPatch\.dylib\""),
    "original order verification": (packager, r"required_original_order.*LEGACY_TWEAK_LOAD_PATH.*BLATANT_LOAD_PATH.*EXISTING_EXTENSION_LOAD_PATH"),
    "output order verification": (packager, r"expected_order.*LEGACY_TWEAK_LOAD_PATH.*BLATANT_LOAD_PATH.*UI_LOAD_PATH.*EXISTING_EXTENSION_LOAD_PATH"),
    "UI inserted before existing extension": (packager, r"insert_load_dylib_before.*EXISTING_EXTENSION_LOAD_PATH"),
    "promotion callback verification": (packager, r"promotionCallbackDisabled"),
    "host bootstrap byte verification": (packager, r"hostInitializersPreserved"),
    "shell discovers real root": (coordinator, r"findTabController"),
    "shell resolves selected tab": (coordinator, r"selectedTab\("),
    "shell signals workspace readiness": (coordinator, r"AEMotionLaunchOverlay\.markShellReady\(\)"),
    "official channel is post-workspace only": (launch, r"markShellReady.*preferredExistingApplicationWindow.*window\.addSubview"),
}

failed = [
    name for name, (text, pattern) in checks.items()
    if re.search(pattern, text, re.S | re.I) is None
]

forbidden = {
    "whole initializer return patch": r"PROMOTION_INITIALIZER.*RETURN_INSTRUCTION|INITIALIZER_LOCAL_OFFSET\s*=\s*0x(?:57C0|5910)",
    "startup key-window takeover": r"makeKeyAndVisible|UIWindow\s*\(",
    "shell-ready loading gate": r"guard\s+isShellReady",
}
for name, pattern in forbidden.items():
    if re.search(pattern, packager + "\n" + launch, re.S | re.I):
        failed.append(name)

if failed:
    print("FAIL: " + ", ".join(failed))
    sys.exit(1)
print("PASS: Build 849 host bootstrap preservation contract")
