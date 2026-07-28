#!/usr/bin/env python3
from __future__ import annotations

import argparse
import importlib.util
from pathlib import Path
import sys
import zipfile

SCRIPT = Path(__file__).with_name("package-ui272-build847-launch-bootstrap-hotfix.py")
spec = importlib.util.spec_from_file_location("build847_bootstrap_hotfix", SCRIPT)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
sys.modules[spec.name] = module
spec.loader.exec_module(module)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("ipa", type=Path)
    args = parser.parse_args()

    failures: list[str] = []
    try:
        with zipfile.ZipFile(args.ipa, "r") as archive:
            main_name, ui_name, host_name = module.app_paths(archive)
            order = module.relevant_order(archive.read(main_name))
            if order != module.EXPECTED_AFTER:
                failures.append(f"launch order is {order!r}")
            ui = archive.read(ui_name)
            host = archive.read(host_name)
            if not all(token in ui for token in module.TELEGRAM_TOKENS):
                failures.append("official Telegram tokens are missing")
            if ui[module.UI_OVERLAY_ENTRY:module.UI_OVERLAY_ENTRY + 4] == module.RETURN:
                failures.append("UI launch overlay was disabled")
            if host[module.HOST_OVERLAY_ENTRY:module.HOST_OVERLAY_ENTRY + 4] == module.RETURN:
                failures.append("host launch overlay was disabled")
            bad = archive.testzip()
            if bad is not None:
                failures.append(f"CRC failure: {bad}")
    except (OSError, zipfile.BadZipFile, module.HotfixError) as error:
        failures.append(str(error))

    if failures:
        print("FAIL: " + "; ".join(failures))
        return 1
    print("PASS: Build 847 launch bootstrap order repaired and Telegram page preserved")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
