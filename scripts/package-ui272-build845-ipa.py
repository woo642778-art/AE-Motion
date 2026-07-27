#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import os
import plistlib
from pathlib import Path
import zipfile

SCRIPT = Path(__file__).with_name("package-ui272-ipa.py")
spec = importlib.util.spec_from_file_location("package_ui272_build845", SCRIPT)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)

from macho_load_command import inspect_macho, insert_load_dylib_before, remove_load_dylib

module.BUILD_NUMBER = 845
LEGACY_TWEAK_LOAD_PATH = "@rpath/AlightMotion.dylib"
BLATANT_LOAD_PATH = "@rpath/blatantsPatch.dylib"
BLATANT_RELATIVE = Path("Frameworks/blatantsPatch.dylib")
OLD_BRANDING_TEXT = "Cracked By Blatant 👀"
NEW_BRANDING_TEXT = "AE Motion Official   "
OLD_BRANDING_UTF16 = OLD_BRANDING_TEXT.encode("utf-16le")
NEW_BRANDING_UTF16 = NEW_BRANDING_TEXT.encode("utf-16le")
DIAGNOSTIC_DISPLAY_NAME = "AE Motion 845"
UNSAFE_PROMOTION_SELECTOR = b"showTitle:title:subTitle:duration:completeText:"
UNSAFE_RUNTIME_REPLACEMENT = b"method_setImplementation"

if len(OLD_BRANDING_UTF16) != len(NEW_BRANDING_UTF16):
    raise RuntimeError("replacement branding must preserve UTF-16 byte length")

_original_apply_verified_fixes = module.apply_verified_2_7_fixes
_original_update_release_metadata = module.update_release_metadata
_original_verify_output = module.verify_output


def patch_legacy_branding(data: bytes) -> bytes:
    occurrences = data.count(OLD_BRANDING_UTF16)
    if occurrences != 2:
        raise module.PackageError(
            f"expected exactly two UTF-16 legacy branding strings, found {occurrences}"
        )
    patched = data.replace(OLD_BRANDING_UTF16, NEW_BRANDING_UTF16)
    if OLD_BRANDING_UTF16 in patched or OLD_BRANDING_TEXT.encode("utf-8") in patched:
        raise module.PackageError("legacy branding token remains after patch")
    return patched


def apply_verified_2_7_fixes(app: Path) -> dict[str, str]:
    result = _original_apply_verified_fixes(app)

    promotion = app / module.PROMOTION_RELATIVE
    promotion.write_bytes(patch_legacy_branding(promotion.read_bytes()))
    patched_hash = module.sha256_file(promotion)
    module.PATCHED_PROMOTION_DYLIB_SHA256 = patched_hash
    result[module.PROMOTION_RELATIVE.as_posix()] = patched_hash

    blatant = app / BLATANT_RELATIVE
    if not blatant.is_file():
        raise module.PackageError("Blatant compatibility dylib is missing from baseline")
    blatant.unlink()
    return result


def patch_main_executable(app: Path) -> dict[str, object]:
    path = app / module.MAIN_RELATIVE
    original = path.read_bytes()
    before = inspect_macho(original)

    if before.dylib_paths.count(module.EXISTING_EXTENSION_LOAD_PATH) != 1:
        raise module.PackageError("existing AE Motion extension load command is missing or duplicated")
    if before.dylib_paths.count(LEGACY_TWEAK_LOAD_PATH) != 1:
        raise module.PackageError("legacy tweak load command is missing or duplicated")
    if before.dylib_paths.count(BLATANT_LOAD_PATH) != 1:
        raise module.PackageError("Blatant load command is missing or duplicated")

    without_blatant = remove_load_dylib(original, BLATANT_LOAD_PATH)
    patched = insert_load_dylib_before(
        without_blatant,
        module.UI_LOAD_PATH,
        LEGACY_TWEAK_LOAD_PATH,
    )
    after = inspect_macho(patched)

    if BLATANT_LOAD_PATH in after.dylib_paths:
        raise module.PackageError("Blatant load command removal failed")
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
        "promotionPatchLoadCommandRemoved": True,
        "uiLoadsBeforeLegacyTweak": True,
    }


def update_release_metadata(app: Path) -> None:
    _original_update_release_metadata(app)
    path = app / module.INFO_RELATIVE
    value = plistlib.loads(path.read_bytes())
    value["CFBundleDisplayName"] = DIAGNOSTIC_DISPLAY_NAME
    value["AEMotionDeviceCandidate"] = "Build 845 crash recovery"
    path.write_bytes(plistlib.dumps(value, fmt=plistlib.FMT_XML, sort_keys=True))


def verify_preservation(
    before: dict[str, str],
    after: dict[str, str],
    removed_signing: list[str],
) -> None:
    mutable = {
        module.MAIN_RELATIVE.as_posix(),
        module.PROMOTION_RELATIVE.as_posix(),
        module.EXTENSION_RELATIVE.as_posix(),
        module.INFO_RELATIVE.as_posix(),
    }
    allowed_removed = {BLATANT_RELATIVE.as_posix()}
    removed_prefixes = tuple(
        entry.rstrip("/") + "/"
        for entry in removed_signing
        if entry.endswith("_CodeSignature")
    )
    removed_exact = set(removed_signing) | allowed_removed

    for path, digest in before.items():
        if path in mutable or path in removed_exact or path.startswith(removed_prefixes):
            continue
        actual = after.get(path)
        if actual != digest:
            raise module.PackageError(f"unexpected baseline file change: {path}")

    for path in after:
        if path in before:
            continue
        if not (
            path.startswith(f"Frameworks/{module.UI_FRAMEWORK_NAME}/")
            or path == module.MANIFEST_NAME
        ):
            raise module.PackageError(f"unexpected added file: {path}")


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

        if prefix + BLATANT_RELATIVE.as_posix() in names:
            raise module.PackageError("Blatant dylib file remains in output")

        main = archive.read(prefix + module.MAIN_RELATIVE.as_posix())
        info = inspect_macho(main)
        if BLATANT_LOAD_PATH in info.dylib_paths:
            raise module.PackageError("Blatant load command remains in output")
        if info.dylib_paths.index(module.UI_LOAD_PATH) >= info.dylib_paths.index(LEGACY_TWEAK_LOAD_PATH):
            raise module.PackageError("output UI framework load order is incorrect")

        promotion = archive.read(prefix + module.PROMOTION_RELATIVE.as_posix())
        if OLD_BRANDING_UTF16 in promotion or OLD_BRANDING_TEXT.encode("utf-8") in promotion:
            raise module.PackageError("legacy branding token remains in output")
        if promotion.count(NEW_BRANDING_UTF16) != 2:
            raise module.PackageError("replacement branding count is incorrect")

        ui_binary_name = (
            prefix
            + f"Frameworks/{module.UI_FRAMEWORK_NAME}/{module.UI_EXECUTABLE_NAME}"
        )
        ui_binary = archive.read(ui_binary_name)
        if UNSAFE_PROMOTION_SELECTOR in ui_binary:
            raise module.PackageError("unsafe promotion selector hook remains in UI framework")
        if UNSAFE_RUNTIME_REPLACEMENT in ui_binary:
            raise module.PackageError("unsafe runtime method replacement remains in UI framework")

        app_info = plistlib.loads(archive.read(prefix + module.INFO_RELATIVE.as_posix()))
        if app_info.get("CFBundleDisplayName") != DIAGNOSTIC_DISPLAY_NAME:
            raise module.PackageError("Build 845 diagnostic display name is missing")

    report["blatantDylibRemoved"] = True
    report["blatantLoadCommandRemoved"] = True
    report["legacyPromotionBrandingRemoved"] = True
    report["unsafeRuntimePromotionHookRemoved"] = True
    report["diagnosticDisplayName"] = DIAGNOSTIC_DISPLAY_NAME
    return report


module.apply_verified_2_7_fixes = apply_verified_2_7_fixes
module.patch_main_executable = patch_main_executable
module.update_release_metadata = update_release_metadata
module.verify_preservation = verify_preservation
module.verify_output = verify_output

if __name__ == "__main__":
    raise SystemExit(module.main())
