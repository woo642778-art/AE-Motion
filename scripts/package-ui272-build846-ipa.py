#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import os
import plistlib
from pathlib import Path
import struct
import zipfile

SCRIPT = Path(__file__).with_name("package-ui272-ipa.py")
spec = importlib.util.spec_from_file_location("package_ui272_build846", SCRIPT)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)

from macho_load_command import inspect_macho, insert_load_dylib_before

module.BUILD_NUMBER = 846
BUILD_NUMBER = 846
LEGACY_TWEAK_LOAD_PATH = "@rpath/AlightMotion.dylib"
BLATANT_LOAD_PATH = "@rpath/blatantsPatch.dylib"
BLATANT_RELATIVE = Path("Frameworks/blatantsPatch.dylib")
BLATANT_BASELINE_SHA256 = "a8fd612fb190a8cb2f1156d3d23af910c8fd166fd1657c6fb4679b88ee81e70b"
DIAGNOSTIC_DISPLAY_NAME = "AE Motion 846"

# The first constructor is at local offset 0x4000 in both universal slices.
# arm64 begins fd7bbfa9, arm64e begins 7f2303d5, and both are replaced by c0035fd6 (ret).
INITIALIZER_LOCAL_OFFSET = 0x4000
ARM64_EXPECTED = bytes.fromhex("fd7bbfa9")
ARM64E_EXPECTED = bytes.fromhex("7f2303d5")
RETURN_INSTRUCTION = bytes.fromhex("c0035fd6")
FAT_MAGIC = 0xCAFEBABE
CPU_TYPE_ARM64 = 0x0100000C
CPU_SUBTYPE_ARM64E = 2

OLD_BRANDING_TEXT = "Cracked By Blatant 👀"
NEW_BRANDING_TEXT = "AE Motion Official   "
OLD_BRANDING_UTF16 = OLD_BRANDING_TEXT.encode("utf-16le")
NEW_BRANDING_UTF16 = NEW_BRANDING_TEXT.encode("utf-16le")

if len(OLD_BRANDING_UTF16) != len(NEW_BRANDING_UTF16):
    raise RuntimeError("replacement branding must preserve UTF-16 byte length")

_original_apply_verified_fixes = module.apply_verified_2_7_fixes
_original_update_release_metadata = module.update_release_metadata
_original_verify_output = module.verify_output


def universal_arm64_slices(data: bytes) -> list[tuple[int, int, int]]:
    if len(data) < 8 or struct.unpack_from(">I", data, 0)[0] != FAT_MAGIC:
        raise module.PackageError("AlightMotion.dylib is not the expected universal Mach-O")
    count = struct.unpack_from(">I", data, 4)[0]
    slices: list[tuple[int, int, int]] = []
    cursor = 8
    for _ in range(count):
        cputype, cpusubtype, offset, size, _align = struct.unpack_from(">IIIII", data, cursor)
        cursor += 20
        if cputype == CPU_TYPE_ARM64:
            slices.append((cpusubtype & 0x00FFFFFF, offset, size))
    if len(slices) != 2:
        raise module.PackageError(f"expected arm64 and arm64e slices, found {len(slices)}")
    return slices


def patch_legacy_promotion_initializer(data: bytes) -> tuple[bytes, list[dict[str, object]]]:
    patched = bytearray(data)
    records: list[dict[str, object]] = []
    for subtype, offset, size in universal_arm64_slices(data):
        location = offset + INITIALIZER_LOCAL_OFFSET
        if location + 4 > offset + size:
            raise module.PackageError("initializer offset lies outside Mach-O slice")
        expected = ARM64E_EXPECTED if subtype == CPU_SUBTYPE_ARM64E else ARM64_EXPECTED
        actual = bytes(patched[location:location + 4])
        if actual != expected:
            raise module.PackageError(
                f"unexpected initializer bytes for subtype {subtype}: {actual.hex()}"
            )
        patched[location:location + 4] = RETURN_INSTRUCTION
        records.append({
            "cpuSubtype": subtype,
            "sliceOffset": offset,
            "initializerOffset": location,
            "originalBytes": actual.hex(),
            "patchedBytes": RETURN_INSTRUCTION.hex(),
        })
    return bytes(patched), records


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
    data = patch_legacy_branding(promotion.read_bytes())
    data, records = patch_legacy_promotion_initializer(data)
    promotion.write_bytes(data)
    patched_hash = module.sha256_file(promotion)
    module.PATCHED_PROMOTION_DYLIB_SHA256 = patched_hash
    result[module.PROMOTION_RELATIVE.as_posix()] = patched_hash

    compatibility = app / BLATANT_RELATIVE
    if not compatibility.is_file():
        raise module.PackageError("blatantsPatch compatibility dylib is missing")
    if module.sha256_file(compatibility) != BLATANT_BASELINE_SHA256:
        raise module.PackageError("blatantsPatch compatibility dylib changed unexpectedly")
    result["legacyPromotionInitializerRecords"] = records  # type: ignore[assignment]
    return result


def patch_main_executable(app: Path) -> dict[str, object]:
    path = app / module.MAIN_RELATIVE
    original = path.read_bytes()
    before = inspect_macho(original)
    for load_path in (
        module.EXISTING_EXTENSION_LOAD_PATH,
        LEGACY_TWEAK_LOAD_PATH,
        BLATANT_LOAD_PATH,
    ):
        if before.dylib_paths.count(load_path) != 1:
            raise module.PackageError(f"required load command missing or duplicated: {load_path}")

    patched = insert_load_dylib_before(
        original,
        module.UI_LOAD_PATH,
        LEGACY_TWEAK_LOAD_PATH,
    )
    after = inspect_macho(patched)
    if after.dylib_paths.count(module.UI_LOAD_PATH) != 1:
        raise module.PackageError("UI framework load command verification failed")
    if after.dylib_paths.index(module.UI_LOAD_PATH) >= after.dylib_paths.index(LEGACY_TWEAK_LOAD_PATH):
        raise module.PackageError("UI framework does not initialize before AlightMotion.dylib")
    if after.dylib_paths.count(BLATANT_LOAD_PATH) != 1:
        raise module.PackageError("blatantsPatch compatibility load command was not preserved")
    if after.dylib_paths.count(module.EXISTING_EXTENSION_LOAD_PATH) != 1:
        raise module.PackageError("existing AE Motion extension load command changed")
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
        "blatantsPatchCompatibilityPreserved": True,
    }


def update_release_metadata(app: Path) -> None:
    _original_update_release_metadata(app)
    path = app / module.INFO_RELATIVE
    value = plistlib.loads(path.read_bytes())
    value["CFBundleDisplayName"] = DIAGNOSTIC_DISPLAY_NAME
    value["AEMotionDeviceCandidate"] = "Build 846 initializer and root routing recovery"
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

        compatibility_name = prefix + BLATANT_RELATIVE.as_posix()
        if compatibility_name not in names:
            raise module.PackageError("blatantsPatch compatibility dylib was removed")
        if module.sha256_bytes(archive.read(compatibility_name)) != BLATANT_BASELINE_SHA256:
            raise module.PackageError("blatantsPatch compatibility dylib was modified")

        main = archive.read(prefix + module.MAIN_RELATIVE.as_posix())
        main_info = inspect_macho(main)
        if main_info.dylib_paths.count(BLATANT_LOAD_PATH) != 1:
            raise module.PackageError("blatantsPatch compatibility load command was not preserved")
        if main_info.dylib_paths.index(module.UI_LOAD_PATH) >= main_info.dylib_paths.index(LEGACY_TWEAK_LOAD_PATH):
            raise module.PackageError("output UI framework load order is incorrect")

        promotion = archive.read(prefix + module.PROMOTION_RELATIVE.as_posix())
        if OLD_BRANDING_UTF16 in promotion or OLD_BRANDING_TEXT.encode("utf-8") in promotion:
            raise module.PackageError("legacy branding token remains in output")
        for subtype, offset, _size in universal_arm64_slices(promotion):
            location = offset + INITIALIZER_LOCAL_OFFSET
            if promotion[location:location + 4] != RETURN_INSTRUCTION:
                raise module.PackageError(f"legacy promotion initializer remains active for subtype {subtype}")

        app_info = plistlib.loads(archive.read(prefix + module.INFO_RELATIVE.as_posix()))
        if app_info.get("CFBundleDisplayName") != DIAGNOSTIC_DISPLAY_NAME:
            raise module.PackageError("Build 846 diagnostic display name is missing")

    report["legacyPromotionInitializerDisabled"] = True
    report["blatantsPatchCompatibilityPreserved"] = True
    report["legacyPromotionBrandingRemoved"] = True
    report["diagnosticDisplayName"] = DIAGNOSTIC_DISPLAY_NAME
    return report


module.apply_verified_2_7_fixes = apply_verified_2_7_fixes
module.patch_main_executable = patch_main_executable
module.update_release_metadata = update_release_metadata
module.verify_output = verify_output

if __name__ == "__main__":
    raise SystemExit(module.main())
