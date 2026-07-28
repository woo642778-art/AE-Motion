#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import zipfile

SCRIPT = Path(__file__).with_name("package-ui272-ipa.py")
spec = importlib.util.spec_from_file_location("package_ui272_build844", SCRIPT)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)

from macho_load_command import inspect_macho, insert_load_dylib_before

module.BUILD_NUMBER = 844
LEGACY_TWEAK_LOAD_PATH = "@rpath/AlightMotion.dylib"
OLD_BRANDING_TEXT = "Cracked By Blatant 👀"
NEW_BRANDING_TEXT = "AE Motion Official   "
OLD_BRANDING_UTF16 = OLD_BRANDING_TEXT.encode("utf-16le")
NEW_BRANDING_UTF16 = NEW_BRANDING_TEXT.encode("utf-16le")

if len(OLD_BRANDING_UTF16) != len(NEW_BRANDING_UTF16):
    raise RuntimeError("replacement branding must preserve UTF-16 byte length")

_original_apply_verified_fixes = module.apply_verified_2_7_fixes
_original_verify_output = module.verify_output


def patch_legacy_branding(data: bytes) -> bytes:
    occurrences = data.count(OLD_BRANDING_UTF16)
    if occurrences != 2:
        raise module.PackageError(
            f"expected exactly two UTF-16 legacy branding strings, found {occurrences}"
        )
    patched = data.replace(OLD_BRANDING_UTF16, NEW_BRANDING_UTF16)
    if OLD_BRANDING_UTF16 in patched or OLD_BRANDING_TEXT.encode("utf-8") in patched:
        raise module.PackageError("legacy branding remains after patch")
    return patched


def apply_verified_2_7_fixes(app: Path) -> dict[str, str]:
    result = _original_apply_verified_fixes(app)
    promotion = app / module.PROMOTION_RELATIVE
    promotion.write_bytes(patch_legacy_branding(promotion.read_bytes()))
    patched_hash = module.sha256_file(promotion)
    module.PATCHED_PROMOTION_DYLIB_SHA256 = patched_hash
    result[module.PROMOTION_RELATIVE.as_posix()] = patched_hash
    return result


def patch_main_executable(app: Path) -> dict[str, object]:
    path = app / module.MAIN_RELATIVE
    original = path.read_bytes()
    before = inspect_macho(original)
    if before.dylib_paths.count(module.EXISTING_EXTENSION_LOAD_PATH) != 1:
        raise module.PackageError("existing AE Motion extension load command is missing or duplicated")
    if before.dylib_paths.count(LEGACY_TWEAK_LOAD_PATH) != 1:
        raise module.PackageError("legacy tweak load command is missing or duplicated")

    patched = insert_load_dylib_before(
        original,
        module.UI_LOAD_PATH,
        LEGACY_TWEAK_LOAD_PATH,
    )
    after = inspect_macho(patched)
    if after.dylib_paths.count(module.UI_LOAD_PATH) != 1:
        raise module.PackageError("UI framework load command verification failed")
    if after.dylib_paths.index(module.UI_LOAD_PATH) >= after.dylib_paths.index(LEGACY_TWEAK_LOAD_PATH):
        raise module.PackageError("UI framework does not initialize before the legacy tweak")
    if after.dylib_paths.count(module.EXISTING_EXTENSION_LOAD_PATH) != 1:
        raise module.PackageError("existing extension load command changed")
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
        "uiLoadsBeforeLegacyTweak": True,
    }


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
        info = inspect_macho(main)
        if info.dylib_paths.index(module.UI_LOAD_PATH) >= info.dylib_paths.index(LEGACY_TWEAK_LOAD_PATH):
            raise module.PackageError("output UI framework load order is incorrect")

        promotion = archive.read(prefix + module.PROMOTION_RELATIVE.as_posix())
        if OLD_BRANDING_UTF16 in promotion or OLD_BRANDING_TEXT.encode("utf-8") in promotion:
            raise module.PackageError("legacy branding token remains in output")
        if promotion.count(NEW_BRANDING_UTF16) != 2:
            raise module.PackageError("replacement branding count is incorrect")

    report["uiLoadsBeforeLegacyTweak"] = True
    report["legacyPromotionBrandingRemoved"] = True
    report["legacyCompatibilityDylibsPreserved"] = True
    return report


module.apply_verified_2_7_fixes = apply_verified_2_7_fixes
module.patch_main_executable = patch_main_executable
module.verify_output = verify_output

if __name__ == "__main__":
    raise SystemExit(module.main())
