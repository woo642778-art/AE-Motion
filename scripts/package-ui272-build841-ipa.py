#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
from pathlib import Path

CORE_SCRIPT = Path(__file__).with_name("package-ui272-ipa.py")
spec = importlib.util.spec_from_file_location("package_ui272_core", CORE_SCRIPT)
core = importlib.util.module_from_spec(spec)
assert spec.loader
spec.loader.exec_module(core)
core.BUILD_NUMBER = 841

for name in dir(core):
    if not name.startswith("_"):
        globals()[name] = getattr(core, name)

if __name__ == "__main__":
    raise SystemExit(core.main())
