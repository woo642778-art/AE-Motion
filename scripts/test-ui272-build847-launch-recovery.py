#!/usr/bin/env python3
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
launch = (ROOT / "Sources/AEMotionUI271Host/AEMotionLaunchOverlay.swift").read_text(encoding="utf-8")
release = (ROOT / "Sources/AEMotionExtensionsCore/AEMotionRelease.swift").read_text(encoding="utf-8")
build = (ROOT / "scripts/build-ios-framework.sh").read_text(encoding="utf-8")
packager_path = ROOT / "scripts/package-ui272-build847-ipa.py"
packager = packager_path.read_text(encoding="utf-8") if packager_path.exists() else ""

checks = {
    "minimum timer transitions without shell gate": (launch, r"asyncAfter\(deadline: \.now\(\) \+ minimumVisibleDuration\).*finishLoadingPhase\(\)"),
    "loading transition not gated by shell": (launch, r"private static func finishLoadingPhase\(\).*didReachMinimumDuration.*!didTransitionFromLoading"),
    "hard maximum dismissal": (launch, r"maximumVisibleDuration.*dismissOverlay\(animated: true\)"),
    "one-shot dismissal": (launch, r"isFinished\s*=\s*true.*presentationGeneration\s*\+=\s*1"),
    "key window restoration": (launch, r"restoreApplicationKeyWindow.*makeKey\(\)"),
    "Build 847 launch marker": (launch, r"Build 847"),
    "Build 847 release": (release + build, r"buildNumber\s*=\s*847.*CFBundleVersion\": \"847\""),
    "real arm64 promotion initializer": (packager, r"0x57c0.*f657bda9.*c0035fd6"),
    "real arm64e promotion initializer": (packager, r"0x5910.*7f2303d5.*c0035fd6"),
    "first initializer preserved": (packager, r"0x4000.*fd7bbfa9.*7f2303d5.*preserv"),
    "compatibility dylib preserved": (packager, r"blatantsPatch.*preserv"),
    "init offset table verification": (packager, r"__init_offsets|INIT_OFFSETS"),
}

failed = [
    name
    for name, (text, pattern) in checks.items()
    if re.search(pattern, text, re.S | re.I) is None
]
if re.search(r"guard\s+isShellReady", launch):
    failed.append("forbidden shell-ready loading gate")
if re.search(r"INITIALIZER_LOCAL_OFFSET\s*=\s*0x4000", packager):
    failed.append("forbidden first-initializer patch")

if failed:
    print("FAIL: " + ", ".join(failed))
    sys.exit(1)
print("PASS: Build 847 launch recovery contract")
