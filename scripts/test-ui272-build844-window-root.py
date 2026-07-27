#!/usr/bin/env python3
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
coordinator = (ROOT / "Sources/AEMotionUI271Host/AEMotionGlobalShellCoordinator.swift").read_text(encoding="utf-8")
shell = (ROOT / "Sources/AEMotionUI271Host/AEMotionShellViewController.swift").read_text(encoding="utf-8")
container_path = ROOT / "Sources/AEMotionUI271Host/AEMotionRootContainerViewController.swift"
container = container_path.read_text(encoding="utf-8") if container_path.exists() else ""
suppressor_path = ROOT / "Sources/AEMotionUI271Host/AEMotionLegacyPromotionSuppressor.swift"
suppressor = suppressor_path.read_text(encoding="utf-8") if suppressor_path.exists() else ""
packager_path = ROOT / "scripts/package-ui272-build844-ipa.py"
packager = packager_path.read_text(encoding="utf-8") if packager_path.exists() else ""
macho = (ROOT / "scripts/macho_load_command.py").read_text(encoding="utf-8")
release = (ROOT / "Sources/AEMotionExtensionsCore/AEMotionRelease.swift").read_text(encoding="utf-8")
build = (ROOT / "scripts/build-ios-framework.sh").read_text(encoding="utf-8")

checks = {
    "root container exists": (container, r"final class AEMotionRootContainerViewController"),
    "original root embedded": (container, r"hostController.*addChild\(hostController\)"),
    "shell embedded above host": (container, r"addChild\(shellController\).*bringSubviewToFront"),
    "main window root replaced once": (coordinator, r"window\.rootViewController\s*=\s*container"),
    "window selected by full-screen area": (coordinator, r"bounds\.width\s*\*\s*.*bounds\.height"),
    "shell no longer constrained to host view": (shell, r"func configure\(tab:.*showsHomeContent:"),
    "project center touch passthrough": (shell, r"interactiveRegions.*hitTest.*return nil"),
    "promotion selector suppressed": (suppressor, r"showTitle:title:subTitle:duration:completeText:"),
    "promotion implementation replaced": (suppressor, r"method_setImplementation|class_replaceMethod"),
    "UI dylib inserted before legacy tweak": (macho + packager, r"insert_load_dylib_before\(.*AlightMotion\.dylib"),
    "UTF16 branding patched": (packager, r"Cracked By Blatant.*encode\(\"utf-16le\"\).*AE Motion Official"),
    "output rejects legacy branding": (packager, r"legacy branding remains|legacy branding token remains"),
    "Build 844 identity": (release + build + packager, r"buildNumber\s*=\s*844.*CFBundleVersion\": \"844\".*BUILD_NUMBER\s*=\s*844"),
}

failed = [name for name, (text, pattern) in checks.items() if re.search(pattern, text, re.S) is None]
if "attach(to host:" in shell or "host.view.addSubview(view)" in shell:
    failed.append("obsolete partial-host attachment remains")
if "remove_load_dylib(original, BLATANT_LOAD_PATH)" in packager:
    failed.append("unrelated app-group compatibility dylib is still removed")
if failed:
    print("FAIL: " + ", ".join(failed))
    sys.exit(1)
print("PASS: Build 844 full-window root, touch routing, and legacy promotion contract")
