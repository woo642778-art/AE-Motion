#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import os
import plistlib
from pathlib import Path
import zipfile

SCRIPT = Path(__file__).with_name("package-ui272-ipa.py")
spec = importlib.util.spec_from_file_location("package_ui272_build851_parent", SCRIPT)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)

from macho_load_command import inspect_macho, insert_load_dylib_before

module.BUILD_NUMBER = 851
BUILD_NUMBER = 851
DIAGNOSTIC_DISPLAY_NAME = "AE Motion 851"
ALIGHT_MOTION_LOAD_PATH = "@rpath/AlightMotion.dylib"
BLATANT_LOAD_PATH = "@rpath/blatantsPatch.dylib"

_original_apply_verified_fixes = module.apply_verified_2_7_fixes
_original_update_release_metadata = module.update_release_metadata
_original_verify_output = module.verify_output

BYTE_SAFE_BRANDING_REPLACEMENTS = (
    ("Cracked By", "AE Motion "),
    ("Blatant", "AE Core"),
    ("My Telegram", "AE Telegram"),
    ("t.me/blatants", "t.me/aemotion"),
)
FORBIDDEN_BRANDING = (
    b"Blatant",
    "Blatant".encode("utf-16le"),
    b"Cracked By",
    "Cracked By".encode("utf-16le"),
    b"t.me/blatants",
    "t.me/blatants".encode("utf-16le"),
)


def neutralize_legacy_branding(data: bytes) -> tuple[bytes, dict[str, int]]:
    patched = data
    counts: dict[str, int] = {}
    for old_text, new_text in BYTE_SAFE_BRANDING_REPLACEMENTS:
        if len(old_text.encode("utf-8")) != len(new_text.encode("utf-8")):
            raise module.PackageError(f"UTF-8 replacement length mismatch: {old_text}")
        if len(old_text.encode("utf-16le")) != len(new_text.encode("utf-16le")):
            raise module.PackageError(f"UTF-16 replacement length mismatch: {old_text}")

        utf8_old = old_text.encode("utf-8")
        utf8_new = new_text.encode("utf-8")
        utf16_old = old_text.encode("utf-16le")
        utf16_new = new_text.encode("utf-16le")
        utf8_count = patched.count(utf8_old)
        utf16_count = patched.count(utf16_old)
        if utf8_count:
            patched = patched.replace(utf8_old, utf8_new)
        if utf16_count:
            patched = patched.replace(utf16_old, utf16_new)
        counts[old_text] = utf8_count + utf16_count

    for forbidden in FORBIDDEN_BRANDING:
        if forbidden in patched:
            raise module.PackageError(f"legacy branding remains after neutralization: {forbidden!r}")
    return patched, counts


def apply_verified_2_7_fixes(app: Path) -> dict[str, object]:
    result: dict[str, object] = dict(_original_apply_verified_fixes(app))
    promotion = app / module.PROMOTION_RELATIVE
    patched, counts = neutralize_legacy_branding(promotion.read_bytes())
    promotion.write_bytes(patched)
    module.PATCHED_PROMOTION_DYLIB_SHA256 = module.sha256_file(promotion)
    result[module.PROMOTION_RELATIVE.as_posix()] = module.PATCHED_PROMOTION_DYLIB_SHA256
    result["legacyBrandingReplacementCounts"] = counts
    return result


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
        raise module.PackageError("Build 851 host load order is incorrect")
    if after.dylib_paths.count(module.UI_LOAD_PATH) != 1:
        raise module.PackageError("Build 851 UI load command is missing or duplicated")
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
    value["AEMotionDeviceCandidate"] = "Build 851 structural UI recovery"
    value["AEMotionOfficialChannel"] = "https://t.me/aemotionios"
    path.write_bytes(plistlib.dumps(value, fmt=plistlib.FMT_XML, sort_keys=True))


def verify_no_legacy_branding(archive: zipfile.ZipFile, prefix: str) -> None:
    findings: list[str] = []
    for name in archive.namelist():
        if not name.startswith(prefix) or name.endswith("/"):
            continue
        data = archive.read(name)
        for token in FORBIDDEN_BRANDING:
            if token in data:
                findings.append(f"{name}:{token!r}")
    if findings:
        raise module.PackageError(
            "legacy branding remains in output: " + ", ".join(findings[:20])
        )


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
        verify_no_legacy_branding(archive, prefix)

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
            raise module.PackageError("output Build 851 load order is incorrect")

        promotion = archive.read(prefix + module.PROMOTION_RELATIVE.as_posix())
        if module.sha256_bytes(promotion) != module.PATCHED_PROMOTION_DYLIB_SHA256:
            raise module.PackageError("Build 851 promotion dylib hash is incorrect")

        app_info = plistlib.loads(archive.read(prefix + module.INFO_RELATIVE.as_posix()))
        if app_info.get("CFBundleDisplayName") != DIAGNOSTIC_DISPLAY_NAME:
            raise module.PackageError("Build 851 display name is missing")
        if app_info.get("AEMotionOfficialChannel") != "https://t.me/aemotionios":
            raise module.PackageError("Build 851 official channel metadata is missing")

        framework_info = plistlib.loads(archive.read(
            prefix + f"Frameworks/{module.UI_FRAMEWORK_NAME}/Info.plist"
        ))
        if str(framework_info.get("CFBundleVersion")) != "851":
            raise module.PackageError("Build 851 framework metadata is incorrect")

    report["legacyBrandingOccurrences"] = 0
    report["officialChannel"] = "https://t.me/aemotionios"
    report["hostExecutableSectionsUnchanged"] = True
    report["uiLoadsBeforeAlightMotion"] = True
    report["rootContainerArchitecture"] = True
    report["diagnosticDisplayName"] = DIAGNOSTIC_DISPLAY_NAME
    return report


module.apply_verified_2_7_fixes = apply_verified_2_7_fixes
module.patch_main_executable = patch_main_executable
module.update_release_metadata = update_release_metadata
module.verify_output = verify_output

if __name__ == "__main__":
    raise SystemExit(module.main())
