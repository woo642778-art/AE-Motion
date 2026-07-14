#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

DISPLAY_NAME = "AE motion"
ICON_SPECS = {
    "AEMotionIcon60x60@2x.png": 120,
    "AEMotionIcon60x60@3x.png": 180,
    "AEMotionIcon76x76@2x~ipad.png": 152,
    "AEMotionIcon83.5x83.5@2x~ipad.png": 167,
}


def _resize_with_pillow(source: Path, destination: Path, size: int) -> bool:
    try:
        from PIL import Image
    except ImportError:
        return False
    image = Image.open(source).convert("RGBA")
    image.resize((size, size), Image.Resampling.LANCZOS).save(destination, format="PNG", optimize=True)
    return True


def _resize(source: Path, destination: Path, size: int) -> None:
    if _resize_with_pillow(source, destination, size):
        return
    if shutil.which("sips"):
        subprocess.run(
            ["sips", "-z", str(size), str(size), str(source), "--out", str(destination)],
            check=True,
            stdout=subprocess.DEVNULL,
        )
        return
    raise RuntimeError("Icon resizing requires Pillow or macOS sips.")


def apply_branding(app: Path, icon_source: Path) -> None:
    info_path = app / "Info.plist"
    if not info_path.is_file():
        raise FileNotFoundError(f"Info.plist not found: {info_path}")
    if not icon_source.is_file():
        raise FileNotFoundError(f"Icon image not found: {icon_source}")

    with info_path.open("rb") as handle:
        info = plistlib.load(handle)
    bundle_id = info.get("CFBundleIdentifier")

    info["CFBundleDisplayName"] = DISPLAY_NAME
    info["CFBundleName"] = DISPLAY_NAME
    info["CFBundleIconFiles"] = ["AEMotionIcon60x60", "AEMotionIcon76x76"]
    info["CFBundleIcons"] = {
        "CFBundlePrimaryIcon": {
            "CFBundleIconFiles": ["AEMotionIcon60x60"],
            "UIPrerenderedIcon": False,
        }
    }
    info["CFBundleIcons~ipad"] = {
        "CFBundlePrimaryIcon": {
            "CFBundleIconFiles": [
                "AEMotionIcon60x60",
                "AEMotionIcon76x76",
                "AEMotionIcon83.5x83.5",
            ],
            "UIPrerenderedIcon": False,
        }
    }

    with tempfile.TemporaryDirectory() as tmp:
        temporary = Path(tmp)
        for filename, size in ICON_SPECS.items():
            output = temporary / filename
            _resize(icon_source, output, size)
            shutil.copy2(output, app / filename)

    with info_path.open("wb") as handle:
        plistlib.dump(info, handle, fmt=plistlib.FMT_BINARY, sort_keys=False)

    with info_path.open("rb") as handle:
        verified = plistlib.load(handle)
    if verified.get("CFBundleDisplayName") != DISPLAY_NAME:
        raise RuntimeError("App display name verification failed.")
    if verified.get("CFBundleIdentifier") != bundle_id:
        raise RuntimeError("Bundle identifier changed unexpectedly.")
    for filename in ICON_SPECS:
        if not (app / filename).is_file():
            raise RuntimeError(f"Missing generated app icon: {filename}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("app", type=Path)
    parser.add_argument("icon", type=Path)
    args = parser.parse_args()
    apply_branding(args.app.resolve(), args.icon.resolve())
    print(f'Applied app name "{DISPLAY_NAME}" and {len(ICON_SPECS)} icon assets.')
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
