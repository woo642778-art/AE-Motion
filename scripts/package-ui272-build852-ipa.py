#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import os
import plistlib
from pathlib import Path
import zipfile

PARENT_SCRIPT = Path(__file__).with_name("package-ui272-build851-ipa.py")
spec = importlib.util.spec_from_file_location("package_ui272_build851_parent", PARENT_SCRIPT)
parent = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(parent)

from macho_load_command import inspect_macho, remove_load_dylib

base = parent.module
base.BUILD_NUMBER = 852
BUILD_NUMBER = 852
DISPLAY_NAME = "AE Motion 852"
LEGACY_PROMOTION_LOAD_PATH = "@rpath/blatantsPatch.dylib"
LEGACY_PROMOTION_RELATIVE = Path("Frameworks/blatantsPatch.dylib")

_parent_apply_fixes = base.apply_verified_2_7_fixes
_parent_patch_main = base.patch_main_executable
_parent_copy_ui = base.copy_ui_framework
_parent_update_metadata = base.update_release_metadata
_parent_verify_output = parent._original_verify_output
_parent_verify_preservation = base.verify_preservation

# Exact arm64 functions in the verified AEMotionExtensionsHost binary that own
# the obsolete launch card and Home/Tutorials/Create/Projects/Templates hooks.
LEGACY_UI_PATCHES: dict[int, tuple[bytes, bytes]] = {
    0x190CB0: (bytes.fromhex("eb2bb86d"), bytes.fromhex("c0035fd6")),
    0x2A2E80: (bytes.fromhex("f44fbea9fd7b01a9"), bytes.fromhex("000080d2c0035fd6")),
    0x2A2F74: (bytes.fromhex("f44fbea9fd7b01a9"), bytes.fromhex("000080d2c0035fd6")),
    0x2A3068: (bytes.fromhex("f44fbea9fd7b01a9"), bytes.fromhex("000080d2c0035fd6")),
    0x2A315C: (bytes.fromhex("f44fbea9fd7b01a9"), bytes.fromhex("000080d2c0035fd6")),
    0x2A3250: (bytes.fromhex("f44fbea9fd7b01a9"), bytes.fromhex("000080d2c0035fd6")),
    0x2A3344: (bytes.fromhex("f44fbea9fd7b01a9"), bytes.fromhex("000080d2c0035fd6")),
    0x2A3DA0: (bytes.fromhex("ff0302d1"), bytes.fromhex("c0035fd6")),
}

FORBIDDEN_PROMOTION_TOKENS = (
    b"Blatant",
    b"blatant",
    b"Cracked By",
    b"t.me/blatants",
    "Blatant".encode("utf-16le"),
    "Cracked By".encode("utf-16le"),
    "t.me/blatants".encode("utf-16le"),
)


def neutralize_legacy_ui(binary: bytes) -> tuple[bytes, dict[str, dict[str, str]]]:
    patched = bytearray(binary)
    report: dict[str, dict[str, str]] = {}
    for offset, (expected, replacement) in LEGACY_UI_PATCHES.items():
        actual = bytes(patched[offset:offset + len(expected)])
        if actual != expected:
            raise base.PackageError(
                f"legacy UI patch precondition failed at {offset:#x}: {actual.hex()}"
            )
        patched[offset:offset + len(replacement)] = replacement
        report[f"{offset:#x}"] = {
            "before": expected.hex(),
            "after": replacement.hex(),
        }
    return bytes(patched), report


def apply_verified_2_7_fixes(app: Path) -> dict[str, object]:
    report: dict[str, object] = dict(_parent_apply_fixes(app))

    extension = app / base.EXTENSION_RELATIVE
    patched, legacy_ui_report = neutralize_legacy_ui(extension.read_bytes())
    extension.write_bytes(patched)
    os.chmod(extension, 0o755)
    base.PATCHED_FRAMEWORK_SHA256 = base.sha256_file(extension)
    report[base.EXTENSION_RELATIVE.as_posix()] = base.PATCHED_FRAMEWORK_SHA256
    report["legacyUIFunctionsNeutralized"] = legacy_ui_report

    legacy_promotion = app / LEGACY_PROMOTION_RELATIVE
    if not legacy_promotion.is_file():
        raise base.PackageError("legacy promotion binary is missing before removal")
    legacy_promotion.unlink()
    report["legacyPromotionBinaryRemoved"] = True
    return report


def patch_main_executable(app: Path) -> dict[str, object]:
    report = dict(_parent_patch_main(app))
    path = app / base.MAIN_RELATIVE
    before = path.read_bytes()
    before_info = inspect_macho(before)
    if before_info.dylib_paths.count(LEGACY_PROMOTION_LOAD_PATH) != 1:
        raise base.PackageError("legacy promotion load command is missing or duplicated")

    patched = remove_load_dylib(before, LEGACY_PROMOTION_LOAD_PATH)
    after_info = inspect_macho(patched)
    if LEGACY_PROMOTION_LOAD_PATH in after_info.dylib_paths:
        raise base.PackageError("legacy promotion load command remains")
    if patched[before_info.first_section_offset:] != before[before_info.first_section_offset:]:
        raise base.PackageError("host executable section bytes changed during legacy cutoff")

    path.write_bytes(patched)
    os.chmod(path, 0o755)
    report.update({
        "patchedSHA256": base.sha256_bytes(patched),
        "patchedNcmds": after_info.ncmds,
        "legacyPromotionLoadCommandRemoved": True,
        "loadOrder": [
            base.UI_LOAD_PATH,
            parent.ALIGHT_MOTION_LOAD_PATH,
            base.EXISTING_EXTENSION_LOAD_PATH,
        ],
    })
    return report


def copy_ui_framework(source: Path, app: Path) -> Path:
    destination = _parent_copy_ui(source, app)
    executable = destination / base.UI_EXECUTABLE_NAME
    data = executable.read_bytes()
    old_key = b"aemotion.build851.official-channel-dismissed"
    new_key = b"aemotion.build852.official-channel-dismissed"
    if old_key in data:
        if len(old_key) != len(new_key) or data.count(old_key) != 1:
            raise base.PackageError("official channel key cannot be safely advanced")
        data = data.replace(old_key, new_key)
        executable.write_bytes(data)
        os.chmod(executable, 0o755)
    return destination


def update_release_metadata(app: Path) -> None:
    _parent_update_metadata(app)
    path = app / base.INFO_RELATIVE
    value = plistlib.loads(path.read_bytes())
    value["CFBundleDisplayName"] = DISPLAY_NAME
    value["CFBundleVersion"] = str(BUILD_NUMBER)
    value["AEMotionReleaseBuild"] = BUILD_NUMBER
    value["AEMotionReleaseDisplayVersion"] = f"2.7.2 ({BUILD_NUMBER})"
    value["AEMotionDeviceCandidate"] = "Build 852 legacy cutoff"
    value["AEMotionOfficialChannel"] = "https://t.me/aemotionios"
    path.write_bytes(plistlib.dumps(value, fmt=plistlib.FMT_XML, sort_keys=True))


def verify_preservation(
    before: dict[str, str],
    after: dict[str, str],
    removed_signing: list[str],
) -> None:
    adjusted_before = dict(before)
    adjusted_before.pop(LEGACY_PROMOTION_RELATIVE.as_posix(), None)
    _parent_verify_preservation(adjusted_before, after, removed_signing)


def verify_output(output: Path) -> dict[str, object]:
    report = _parent_verify_output(output)
    with zipfile.ZipFile(output) as archive:
        names = set(archive.namelist())
        apps = sorted({
            name.split("/")[1]
            for name in names
            if name.startswith("Payload/") and ".app/" in name
        })
        prefix = f"Payload/{apps[0]}/"

        if prefix + LEGACY_PROMOTION_RELATIVE.as_posix() in names:
            raise base.PackageError("legacy promotion binary remains in output")

        main = archive.read(prefix + base.MAIN_RELATIVE.as_posix())
        main_info = inspect_macho(main)
        if LEGACY_PROMOTION_LOAD_PATH in main_info.dylib_paths:
            raise base.PackageError("legacy promotion load command remains in output")
        required_order = (
            base.UI_LOAD_PATH,
            parent.ALIGHT_MOTION_LOAD_PATH,
            base.EXISTING_EXTENSION_LOAD_PATH,
        )
        positions = [main_info.dylib_paths.index(item) for item in required_order]
        if positions != sorted(positions):
            raise base.PackageError("Build 852 load order is incorrect")

        extension = archive.read(prefix + base.EXTENSION_RELATIVE.as_posix())
        for offset, (_, replacement) in LEGACY_UI_PATCHES.items():
            if extension[offset:offset + len(replacement)] != replacement:
                raise base.PackageError(f"legacy UI function remains active at {offset:#x}")

        for name in names:
            if not name.startswith(prefix) or name.endswith("/"):
                continue
            data = archive.read(name)
            for token in FORBIDDEN_PROMOTION_TOKENS:
                if token in data:
                    raise base.PackageError(f"forbidden promotion token remains in {name}")

        app_info = plistlib.loads(archive.read(prefix + base.INFO_RELATIVE.as_posix()))
        if str(app_info.get("CFBundleVersion")) != "852":
            raise base.PackageError("Build 852 app metadata is incorrect")
        if app_info.get("CFBundleDisplayName") != DISPLAY_NAME:
            raise base.PackageError("Build 852 display name is incorrect")

        framework_info = plistlib.loads(archive.read(
            prefix + f"Frameworks/{base.UI_FRAMEWORK_NAME}/Info.plist"
        ))
        if str(framework_info.get("CFBundleVersion")) != "852":
            raise base.PackageError("Build 852 framework metadata is incorrect")

    report.update({
        "legacyPromotionLoadCommandRemoved": True,
        "legacyPromotionBinaryRemoved": True,
        "legacyUIFunctionsNeutralized": True,
        "forbiddenPromotionOccurrences": 0,
        "diagnosticDisplayName": DISPLAY_NAME,
    })
    return report


base.apply_verified_2_7_fixes = apply_verified_2_7_fixes
base.patch_main_executable = patch_main_executable
base.copy_ui_framework = copy_ui_framework
base.update_release_metadata = update_release_metadata
base.verify_preservation = verify_preservation
base.verify_output = verify_output

if __name__ == "__main__":
    raise SystemExit(base.main())
