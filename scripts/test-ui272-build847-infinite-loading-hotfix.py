#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path
import zipfile

RETURN_INSTRUCTION = bytes.fromhex("c0035fd6")
PATCHES = {
    "Payload/AlightMotion.app/Frameworks/AEMotionExtensionsHost.framework/AEMotionExtensionsHost": 0x190CB0,
    "Payload/AlightMotion.app/Frameworks/AEMotionUI272.framework/AEMotionUI272": 0x1A548,
}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("ipa", type=Path)
    args = parser.parse_args()

    failures: list[str] = []
    with zipfile.ZipFile(args.ipa, "r") as archive:
        for name, offset in PATCHES.items():
            data = archive.read(name)
            actual = data[offset:offset + 4]
            if actual != RETURN_INSTRUCTION:
                failures.append(f"{name}@0x{offset:x}={actual.hex()}")
        bad = archive.testzip()
        if bad is not None:
            failures.append(f"CRC failure: {bad}")

    if failures:
        print("FAIL: launch overlay entry points remain active: " + "; ".join(failures))
        return 1
    print("PASS: Build 847 infinite-loading launch overlays are disabled")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
