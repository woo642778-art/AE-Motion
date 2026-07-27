#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
from pathlib import Path

SCRIPT = Path(__file__).with_name("package-ui272-build847-ipa.py")
spec = importlib.util.spec_from_file_location("package_ui272_build848_parent", SCRIPT)
build847 = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(build847)

build847.parent.BUILD_NUMBER = 848
build847.parent.module.BUILD_NUMBER = 848
build847.parent.DIAGNOSTIC_DISPLAY_NAME = "AE Motion 848"

# Build 848 intentionally keeps the verified Build 847 Mach-O repair:
# - preserve the first initializer at 0x4000 in both slices;
# - disable only the real promotion initializer at arm64 0x57c0 and arm64e 0x5910;
# - preserve blatantsPatch.dylib and its load command for compatibility.
# The Build 848 change is isolated to the UIKit framework: no startup UIWindow,
# no key-window replacement, and the official channel appears only after the
# existing workspace window is ready.

if __name__ == "__main__":
    raise SystemExit(build847.parent.module.main())
