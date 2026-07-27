#!/usr/bin/env python3
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
package = (ROOT / "Package.swift").read_text(encoding="utf-8")
loader = (ROOT / "Sources/AEMotionUI271Host/LegacyFrameworkLoader.swift").read_text(encoding="utf-8")
installer = (ROOT / "Sources/AEMotionUI271Host/AEMotionUI271Installer.swift").read_text(encoding="utf-8")
bootstrap = (ROOT / "Sources/AEMotionUI271Bootstrap/AEMotionUI271Bootstrap.c").read_text(encoding="utf-8")

checks = {
    "dynamic app-load product": (
        package,
        r'library\(\s*name:\s*"AEMotionExtensionsHost",\s*type:\s*\.dynamic,\s*targets:\s*\["AEMotionUI271Host",\s*"AEMotionUI271Bootstrap"\]',
    ),
    "legacy source product retained": (package, r'AEMotionExtensionsLegacySource'),
    "legacy target renamed": (package, r'name:\s*"AEMotionExtensionsLegacySourceHost"'),
    "legacy target path retained": (package, r'path:\s*"Sources/AEMotionExtensionsHost"'),
    "wrapper host target": (package, r'target\(name:\s*"AEMotionUI271Host"'),
    "wrapper bootstrap target": (package, r'name:\s*"AEMotionUI271Bootstrap"'),
    "legacy filename": (loader, r'AEMotionLegacy'),
    "dlopen": (loader, r'\bdlopen\s*\('),
    "global symbols": (loader, r'RTLD_GLOBAL'),
    "cdecl installer": (installer, r'@_cdecl\("AEMotionUI271Install"\)'),
    "legacy before hooks": (installer, r'loadLegacyFramework\(\).*installRuntimeHooks'),
    "constructor": (bootstrap, r'__attribute__\(\(constructor\)\)'),
}

failed = [name for name, (content, pattern) in checks.items() if re.search(pattern, content, re.S) is None]
if re.search(r'target\(name:\s*"AEMotionExtensionsHost"', package):
    failed.append("legacy target collides with app-load product")
if failed:
    print("FAIL: " + ", ".join(failed))
    sys.exit(1)
print("PASS: UI 2.7.1 legacy wrapper contract")
