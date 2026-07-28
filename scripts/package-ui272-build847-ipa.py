#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import plistlib
from pathlib import Path
import zipfile

SCRIPT = Path(__file__).with_name("package-ui272-build846-ipa.py")
spec = importlib.util.spec_from_file_location("package_ui272_build847_parent", SCRIPT)
parent = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(parent)

parent.BUILD_NUMBER = 847
parent.module.BUILD_NUMBER = 847
parent.DIAGNOSTIC_DISPLAY_NAME = "AE Motion 847"

# S_INIT_FUNC_OFFSETS (__TEXT,__init_offsets) proves the launch dylib has four
# constructors. Build 846 patched the first constructor at 0x4000 by mistake.
# Preserve arm64 0x4000 = fd7bbfa9 and arm64e 0x4000 = 7f2303d5.
ARM64_FIRST_INITIALIZER = 0x4000
ARM64_FIRST_EXPECTED = bytes.fromhex("fd7bbfa9")
ARM64E_FIRST_INITIALIZER = 0x4000
ARM64E_FIRST_EXPECTED = bytes.fromhex("7f2303d5")

# The real promotion initializer registers UIApplicationDidFinishLaunchingNotification
# and creates the legacy alert-level UIWindow.
ARM64_PROMOTION_INITIALIZER = 0x57C0
ARM64_PROMOTION_EXPECTED = bytes.fromhex("f657bda9")
ARM64E_PROMOTION_INITIALIZER = 0x5910
ARM64E_PROMOTION_EXPECTED = bytes.fromhex("7f2303d5")
RETURN_INSTRUCTION = bytes.fromhex("c0035fd6")


def patch_legacy_promotion_initializer(data: bytes):
    patched = bytearray(data)
    records: list[dict[str, object]] = []
    for subtype, offset, size in parent.universal_arm64_slices(data):
        is_arm64e = subtype == parent.CPU_SUBTYPE_ARM64E
        first_local = ARM64E_FIRST_INITIALIZER if is_arm64e else ARM64_FIRST_INITIALIZER
        first_expected = ARM64E_FIRST_EXPECTED if is_arm64e else ARM64_FIRST_EXPECTED
        promotion_local = ARM64E_PROMOTION_INITIALIZER if is_arm64e else ARM64_PROMOTION_INITIALIZER
        promotion_expected = ARM64E_PROMOTION_EXPECTED if is_arm64e else ARM64_PROMOTION_EXPECTED

        first_location = offset + first_local
        promotion_location = offset + promotion_local
        if promotion_location + 4 > offset + size:
            raise parent.module.PackageError("promotion initializer lies outside Mach-O slice")
        if bytes(patched[first_location:first_location + 4]) != first_expected:
            raise parent.module.PackageError(
                f"first initializer was not preserved for subtype {subtype}"
            )
        actual = bytes(patched[promotion_location:promotion_location + 4])
        if actual != promotion_expected:
            raise parent.module.PackageError(
                f"unexpected promotion initializer bytes for subtype {subtype}: {actual.hex()}"
            )
        patched[promotion_location:promotion_location + 4] = RETURN_INSTRUCTION
        records.append({
            "cpuSubtype": subtype,
            "firstInitializerOffset": first_location,
            "firstInitializerPreserved": True,
            "promotionInitializerOffset": promotion_location,
            "originalBytes": actual.hex(),
            "patchedBytes": RETURN_INSTRUCTION.hex(),
        })
    return bytes(patched), records


parent.patch_legacy_promotion_initializer = patch_legacy_promotion_initializer


def verify_output(output: Path) -> dict[str, object]:
    report = parent._original_verify_output(output)
    with zipfile.ZipFile(output) as archive:
        names = set(archive.namelist())
        apps = sorted({
            name.split("/")[1]
            for name in names
            if name.startswith("Payload/") and ".app/" in name
        })
        prefix = f"Payload/{apps[0]}/"

        compatibility_name = prefix + parent.BLATANT_RELATIVE.as_posix()
        if compatibility_name not in names:
            raise parent.module.PackageError("blatantsPatch compatibility dylib was removed")
        if parent.module.sha256_bytes(archive.read(compatibility_name)) != parent.BLATANT_BASELINE_SHA256:
            raise parent.module.PackageError("blatantsPatch compatibility dylib was modified")

        main = archive.read(prefix + parent.module.MAIN_RELATIVE.as_posix())
        main_info = parent.inspect_macho(main)
        if main_info.dylib_paths.count(parent.BLATANT_LOAD_PATH) != 1:
            raise parent.module.PackageError("blatantsPatch compatibility load command was not preserved")
        if main_info.dylib_paths.index(parent.module.UI_LOAD_PATH) >= main_info.dylib_paths.index(parent.LEGACY_TWEAK_LOAD_PATH):
            raise parent.module.PackageError("output UI framework load order is incorrect")

        promotion = archive.read(prefix + parent.module.PROMOTION_RELATIVE.as_posix())
        if parent.OLD_BRANDING_UTF16 in promotion or parent.OLD_BRANDING_TEXT.encode("utf-8") in promotion:
            raise parent.module.PackageError("legacy branding token remains in output")
        for subtype, offset, _size in parent.universal_arm64_slices(promotion):
            is_arm64e = subtype == parent.CPU_SUBTYPE_ARM64E
            first_local = ARM64E_FIRST_INITIALIZER if is_arm64e else ARM64_FIRST_INITIALIZER
            first_expected = ARM64E_FIRST_EXPECTED if is_arm64e else ARM64_FIRST_EXPECTED
            promotion_local = ARM64E_PROMOTION_INITIALIZER if is_arm64e else ARM64_PROMOTION_INITIALIZER
            if promotion[offset + first_local:offset + first_local + 4] != first_expected:
                raise parent.module.PackageError(f"first initializer changed for subtype {subtype}")
            if promotion[offset + promotion_local:offset + promotion_local + 4] != RETURN_INSTRUCTION:
                raise parent.module.PackageError(f"promotion initializer remains active for subtype {subtype}")

        app_info = plistlib.loads(archive.read(prefix + parent.module.INFO_RELATIVE.as_posix()))
        if app_info.get("CFBundleDisplayName") != parent.DIAGNOSTIC_DISPLAY_NAME:
            raise parent.module.PackageError("Build 847 diagnostic display name is missing")

    report["legacyPromotionInitializerDisabled"] = True
    report["firstInitializerPreserved"] = True
    report["blatantsPatchCompatibilityPreserved"] = True
    report["legacyPromotionBrandingRemoved"] = True
    report["diagnosticDisplayName"] = parent.DIAGNOSTIC_DISPLAY_NAME
    report["initOffsetsSectionVerified"] = "__TEXT,__init_offsets"
    return report


parent.module.apply_verified_2_7_fixes = parent.apply_verified_2_7_fixes
parent.module.patch_main_executable = parent.patch_main_executable
parent.module.update_release_metadata = parent.update_release_metadata
parent.module.verify_output = verify_output

if __name__ == "__main__":
    raise SystemExit(parent.module.main())
