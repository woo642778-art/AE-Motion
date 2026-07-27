#!/usr/bin/env python3
from pathlib import Path
import runpy

# Compatibility entry point retained because the existing CI workflow still
# invokes the old filename. The current regression contract is Build 847.
runpy.run_path(
    str(Path(__file__).with_name("test-ui272-build847-launch-recovery.py")),
    run_name="__main__",
)
