#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import os
import plistlib
from pathlib import Path
import struct
import zipfile

SCRIPT = Path(__file__).with_name("package-ui272-ipa.py")
spec = importlib.util.spec_from_file_location("package_ui272_build849_parent", SCRIPT)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)

from macho_load_command import inspect_macho, insert_load_dylib_before

module.BUILD_NUMBER = 849
BUILD_NUMBER = 849
DIAGNOSTIC_DISPLAY_NAME = "AE Motion 849"
LEGACY_TWEAK_LOAD_PATH = "@rpath/AlightMotion.dylib"
BLATANT_LOAD_PATH = "@rpath/blatantsPatch.dylib"

FAT_MAGIC = 0xCAFEBABE
CPU_TYPE_ARM64 = 0x0100000C
CPU_SUBTYPE_ARM64E = 2
RETURN_INSTRUCTION = bytes.fromhex("c0035fd6")

# Preserve the complete constructor table and every initializer body.
INITIALIZER_OFFSETS = {
    0: (0x869C0, (0x4000, 0x42A4, 0x57C0, 0x7514)),
    CPU_SUBTYPE_ARM64E: (0x87D60, (0x4000, 0x42E4, 0x5910, 0x77C0)),
}

# The launch-notification callback only dispatches the legacy alert-window
# construction block. Returning here preserves registration and host bootstrap.
ARM64_PROMOTION_CALLBACK = 0x599C
ARM64E_PROMOTION_CALLBACK = 0x5B14
PROMOTION_CALLBACK_EXPECTED = bytes.fromhex("000700f0")

OLD_BRANDING_TEXT = "Cracked By Blatant 👀"
NEW_BRANDING_TEXT = "AE Motion Official   "
OLD_BRANDING_UTF16 = OLD_BRANDING_TEXT.encode("utf-16le")
NEW_BRANDING_UTF16 = NEW_BRANDING_TEXT.encode("utf-16le")
if len(OLD_BRANDING_UTF16) != len(NEW_BRANDING_UTF16):
    raise RuntimeError("branding replacement must preserve byte length")

_original_apply_verified_fixes = module.apply_verified_2_7_fixes
_original_update_release_metadata = module.update_release_metadata
_original_verify_output = module.verify_output


def universal_arm64_slices(data: bytes) -> list[tuple[int, int, int]]:
    if len(data) < 8 or struct.unpack_from(">I", data, 0)[0] != FAT_MAGIC:
        raise module.PackageError("AlightMotion.dylib is not the expected universal Mach-O")
    count = struct.unpack_from(">I", data, 4)[0]
    result: list[tuple[int, int, int]] = []
    cursor = 8
    for _ in range(count):
        cputype, cpusubtype, offset, size, _align = struct.unpack_from(">IIIII", data, cursor)
        cursor += 20
        if cputype == CPU_TYPE_ARM64:
            result.append((cpusubtype & 0x00FFFFFF, offset, size))
    if len(result) != 2:
        raise module.PackageError(f"expected arm64 and arm64e slices, found {len(result)}")
    return result


def initializer_table(data: bytes, subtype: int, slice_offset: int) -> tuple[int, ...]:
    table_local, expected = INITIALIZER_OFFSETS[subtype]
    location = slice_offset + table_local
    actual = tuple(struct.unpack_from("<IIII", data, location))
    if actual != expected:
        raise module.PackageError(
            f"unexpected __init_offsets for subtype {subtype}: {actual!r}"
        )
    return actual


def patch_promotion_callback_only(data: bytes) -> tuple[bytes, list[dict[str, object]]]:
    patched = bytearray(data)
    records: list[dict[str, object]] = []
    for subtype, slice_offset, slice_size in universal_arm64_slices(data):
        initializers_before = initializer_table(data, subtype, slice_offset)
        callback_local = (
            ARM64E_PROMOTION_CALLBACK
            if subtype == CPU_SUBTYPE_ARM64E
            else ARM64_PROMOTION_CALLBACK
        )
        location = slice_offset + callback_local
        if location + 4 > slice_offset + slice_size:
            raise module.PackageError("promotion callback lies outside Mach-O slice")
        actual = bytes(patched[location:location + 4])
        if actual != PROMOTION_CALLBACK_EXPECTED:
            raise module.PackageError(
                f"unexpected promotion callback bytes for subtype {subtype}: {actual.hex()}"
            )
        patched[location:location + 4] = RETURN_INSTRUCTION
        initializers_after = initializer_table(bytes(patched), subtype, slice_offset)
        if initializers_after != initializers_before:
            raise module.PackageError("host initializer table changed")
        records.append({
            "cpuSubtype": subtype,
            "callbackOffset": location,
            "originalBytes": actual.hex(),
            "patchedBytes": RETURN_INSTRUCTION.hex(),
            "hostInitializersPreserved": list(initializers_after),
        })
    return bytes(patched), records


def apply_verified_2_7_fixes(app: Path) -> dict[str, object]:
    result: dict[str, object] = dict(_original_apply_verified_fixes(app))
    promotion = app / module.PROMOTION_RELATIVE
    data = promotion.read_bytes()

    if data.count(OLD_BRANDING_UTF16) != 2:
        raise module.PackageError("expected two legacy UTF-16 branding strings")
    data = data.replace(OLD_BRANDING_UTF16, NEW_BRANDING_UTF16)
    data, records = patch_promotion_callback_only(data)
    promotion.write_bytes(data)

    patched_hash = module.sha256_file(promotion)
    module.PATCHED_PROMOTION_DYLIB_SHA256 = patched_hash
    result[module.PROMOTION_RELATIVE.as_posix()] = patched_hash
    result["promotionCallbackRecords"] = records
    return result


def patch_main_executable(app: Path) -> dict[str, object]:
    path = app / module.MAIN_RELATIVE
    original = path.read_bytes()
    before = inspect_macho(original)

    required_original_order = (
        LEGACY_TWEAK_LOAD_PATH,
        BLATANT_LOAD_PATH,
        module.EXISTING_EXTENSION_LOAD_PATH,
    )
    positions = []
    for load_path in required_original_order:
        if before.dylib_paths.count(load_path) != 1:
            raise module.PackageError(f"required load command missing or duplicated: {load_path}")
        positions.append(before.dylib_paths.index(load_path))
    if positions != sorted(positions):
        raise module.PackageError("baseline host load order is not original")

    patched = insert_load_dylib_before(
        original,
        module.UI_LOAD_PATH,
        module.EXISTING_EXTENSION_LOAD_PATH,
    )
    after = inspect_macho(patched)
    expected_order = (
        LEGACY_TWEAK_LOAD_PATH,
        BLATANT_LOAD_PATH,
        module.UI_LOAD_PATH,
        module.EXISTING_EXTENSION_LOAD_PATH,
    )
    updated_positions = [after.dylib_paths.index(path) for path in expected_order]
    if updated_positions != sorted(updated_positions):
        raise module.PackageError("Build 849 host load order is incorrect")
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
        "originalHostLoadOrderRetained": list(expected_order),
    }


def update_release_metadata(app: Path) -> None:
    _original_update_release_metadata(app)
    path = app / module.INFO_RELATIVE
    value = plistlib.loads(path.read_bytes())
    value["CFBundleDisplayName"] = DIAGNOSTIC_DISPLAY_NAME
    value["AEMotionDeviceCandidate"] = "Build 849 host-bootstrap preservation"
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
            LEGACY_TWEAK_LOAD_PATH,
            BLATANT_LOAD_PATH,
            module.UI_LOAD_PATH,
            module.EXISTING_EXTENSION_LOAD_PATH,
        )
        positions = [main_info.dylib_paths.index(path) for path in expected_order]
        if positions != sorted(positions):
            raise module.PackageError("output host load order is incorrect")

        promotion = archive.read(prefix + module.PROMOTION_RELATIVE.as_posix())
        for subtype, slice_offset, _slice_size in universal_arm64_slices(promotion):
            initializers = initializer_table(promotion, subtype, slice_offset)
            callback_local = (
                ARM64E_PROMOTION_CALLBACK
                if subtype == CPU_SUBTYPE_ARM64E
                else ARM64_PROMOTION_CALLBACK
            )
            location = slice_offset + callback_local
            if promotion[location:location + 4] != RETURN_INSTRUCTION:
                raise module.PackageError(
                    f"promotion callback remains active for subtype {subtype}"
                )
            if not initializers:
                raise module.PackageError("host initializer table is empty")

        if OLD_BRANDING_UTF16 in promotion:
            raise module.PackageError("legacy Blatant branding remains")
        app_info = plistlib.loads(archive.read(prefix + module.INFO_RELATIVE.as_posix()))
        if app_info.get("CFBundleDisplayName") != DIAGNOSTIC_DISPLAY_NAME:
            raise module.PackageError("Build 849 diagnostic display name is missing")

    report["promotionCallbackDisabled"] = True
    report["hostInitializersPreserved"] = True
    report["originalHostLoadOrderRetained"] = True
    report["legacyBrandingRemoved"] = True
    report["diagnosticDisplayName"] = DIAGNOSTIC_DISPLAY_NAME
    return report


module.apply_verified_2_7_fixes = apply_verified_2_7_fixes
module.patch_main_executable = patch_main_executable
module.update_release_metadata = update_release_metadata
module.verify_output = verify_output

if __name__ == "__main__":
    raise SystemExit(module.main())
