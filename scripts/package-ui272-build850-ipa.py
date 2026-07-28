#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import os
import plistlib
from pathlib import Path
import zipfile

SCRIPT = Path(__file__).with_name("package-ui272-ipa.py")
spec = importlib.util.spec_from_file_location("package_ui272_build850_parent", SCRIPT)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)

from macho_load_command import inspect_macho, insert_load_dylib_before

module.BUILD_NUMBER = 850
BUILD_NUMBER = 850
DIAGNOSTIC_DISPLAY_NAME = "AE Motion 850"
ALIGHT_MOTION_LOAD_PATH = "@rpath/AlightMotion.dylib"
BLATANT_LOAD_PATH = "@rpath/blatantsPatch.dylib"

_original_update_release_metadata = module.update_release_metadata
_original_verify_output = module.verify_output


def patch_main_executable(app: Path) -> dict[str, object]:
    path = app / module.MAIN_RELATIVE
    original = path.read_bytes()
    before = inspect_macho(original)

    for required in (
        ALIGHT_MOTION_LOAD_PATH,
        BLATANT_LOAD_PATH,
        module.EXISTING_EXTENSION_LOAD_PATH,
    ):
        if before.dylib_paths.count(required) != 1:
            raise module.PackageError(f"required load command missing or duplicated: {required}")

    # Build 844 was the last device-observed build that reached the workspace.
    # Restore its load order: install the passive AE Motion UI framework before
    # AlightMotion.dylib, while preserving every existing load command and all
    # executable section bytes.
    patched = insert_load_dylib_before(
        original,
        module.UI_LOAD_PATH,
        ALIGHT_MOTION_LOAD_PATH,
    )
    after = inspect_macho(patched)
    expected_order = (
        module.UI_LOAD_PATH,
        ALIGHT_MOTION_LOAD_PATH,
        BLATANT_LOAD_PATH,
        module.EXISTING_EXTENSION_LOAD_PATH,
    )
    positions = [after.dylib_paths.index(item) for item in expected_order]
    if positions != sorted(positions):
        raise module.PackageError("Build 850 host load order is incorrect")
    if patched[before.first_section_offset:] != original[before.first_section_offset:]:
        raise module.PackageError("host executable section bytes changed")

    path.write_bytes(patched)
    os.chmod(path, 0o755)
    return {
        "originalSHA256": module.sha256_bytes(original),
        "patchedSHA256": module.sha256_bytes(patched),
        "firstSectionOffset": before.first_section_offset,
        "originalNcmds": before.ncmds,
        "patchedNcmds": after.ncmds,
        "sectionBytesUnchanged": True,
        "loadOrder": list(expected_order),
    }


def update_release_metadata(app: Path) -> None:
    _original_update_release_metadata(app)
    path = app / module.INFO_RELATIVE
    value = plistlib.loads(path.read_bytes())
    value["CFBundleDisplayName"] = DIAGNOSTIC_DISPLAY_NAME
    value["AEMotionDeviceCandidate"] = "Build 850 non-invasive bootstrap"
    path.write_bytes(plistlib.dumps(value, fmt=plistlib.FMT_XML, sort_keys=True))


def verify_output(output: Path) -> dict[str, object]:
    report = _original_verify_output(output)
    with zipfile.ZipFile(output) as archive:
        names = set(archive.namelist())
        apps = sorted({
            name.split("/")[1]
            for name in names
            if name.startswith("Payload/") and ".app/" in name
        })
        prefix = f"Payload/{apps[0]}/"

        main = archive.read(prefix + module.MAIN_RELATIVE.as_posix())
        main_info = inspect_macho(main)
        expected_order = (
            module.UI_LOAD_PATH,
            ALIGHT_MOTION_LOAD_PATH,
            BLATANT_LOAD_PATH,
            module.EXISTING_EXTENSION_LOAD_PATH,
        )
        positions = [main_info.dylib_paths.index(item) for item in expected_order]
        if positions != sorted(positions):
            raise module.PackageError("output Build 850 load order is incorrect")

        promotion = archive.read(prefix + module.PROMOTION_RELATIVE.as_posix())
        promotion_hash = module.sha256_bytes(promotion)
        if promotion_hash != module.PATCHED_PROMOTION_DYLIB_SHA256:
            raise module.PackageError(
                "AlightMotion.dylib differs from the verified strings-only patch"
            )

        app_info = plistlib.loads(archive.read(prefix + module.INFO_RELATIVE.as_posix()))
        if app_info.get("CFBundleDisplayName") != DIAGNOSTIC_DISPLAY_NAME:
            raise module.PackageError("Build 850 display name is missing")

    report["promotionCodeBytesUnchanged"] = True
    report["promotionDylibSHA256"] = module.PATCHED_PROMOTION_DYLIB_SHA256
    report["hostExecutableSectionsUnchanged"] = True
    report["uiLoadsBeforeAlightMotion"] = True
    report["rootControllerReplacement"] = False
    report["diagnosticDisplayName"] = DIAGNOSTIC_DISPLAY_NAME
    return report


module.patch_main_executable = patch_main_executable
module.update_release_metadata = update_release_metadata
module.verify_output = verify_output

if __name__ == "__main__":
    raise SystemExit(module.main())
