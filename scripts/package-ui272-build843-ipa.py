#!/usr/bin/env python3
from __future__ import annotations

import argparse
import importlib.util
import os
from pathlib import Path
import zipfile

SCRIPT = Path(__file__).with_name("package-ui272-ipa.py")
spec = importlib.util.spec_from_file_location("package_ui272_build843", SCRIPT)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)

from macho_load_command import append_load_dylib, inspect_macho, remove_load_dylib

module.BUILD_NUMBER = 843
BLATANT_LOAD_PATH = "@rpath/blatantsPatch.dylib"
BLATANT_RELATIVE = Path("Frameworks/blatantsPatch.dylib")

_original_apply_verified_fixes = module.apply_verified_2_7_fixes
_original_verify_output = module.verify_output


def apply_verified_2_7_fixes(app: Path) -> dict[str, str]:
    result = _original_apply_verified_fixes(app)
    blatant = app / BLATANT_RELATIVE
    if blatant.exists():
        blatant.unlink()
    return result


def patch_main_executable(app: Path) -> dict[str, object]:
    path = app / module.MAIN_RELATIVE
    original = path.read_bytes()
    before = inspect_macho(original)
    if before.dylib_paths.count(module.EXISTING_EXTENSION_LOAD_PATH) != 1:
        raise module.PackageError("existing AE Motion extension load command is missing or duplicated")
    if before.dylib_paths.count(BLATANT_LOAD_PATH) != 1:
        raise module.PackageError("expected exactly one Blatant patch load command in baseline")

    without_blatant = remove_load_dylib(original, BLATANT_LOAD_PATH)
    patched = append_load_dylib(without_blatant, module.UI_LOAD_PATH)
    after = inspect_macho(patched)

    if BLATANT_LOAD_PATH in after.dylib_paths:
        raise module.PackageError("Blatant load command removal failed")
    if after.dylib_paths.count(module.UI_LOAD_PATH) != 1:
        raise module.PackageError("UI framework load command verification failed")
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
        "blatantLoadCommandRemoved": True,
    }


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
    removed_prefixes = tuple(entry.rstrip("/") + "/" for entry in removed_signing if entry.endswith("_CodeSignature"))
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
        if not (path.startswith(f"Frameworks/{module.UI_FRAMEWORK_NAME}/") or path == module.MANIFEST_NAME):
            raise module.PackageError(f"unexpected added file: {path}")


def verify_output(output: Path) -> dict[str, object]:
    report = _original_verify_output(output)
    with zipfile.ZipFile(output) as archive:
        names = set(archive.namelist())
        apps = sorted({name.split("/")[1] for name in names if name.startswith("Payload/") and ".app/" in name})
        prefix = f"Payload/{apps[0]}/"
        if prefix + BLATANT_RELATIVE.as_posix() in names:
            raise module.PackageError("Blatant dylib file remains in output")
        main = archive.read(prefix + module.MAIN_RELATIVE.as_posix())
        info = inspect_macho(main)
        if BLATANT_LOAD_PATH in info.dylib_paths:
            raise module.PackageError("Blatant load command remains in output")
    report["blatantDylibRemoved"] = True
    report["blatantLoadCommandRemoved"] = True
    return report


module.apply_verified_2_7_fixes = apply_verified_2_7_fixes
module.patch_main_executable = patch_main_executable
module.verify_preservation = verify_preservation
module.verify_output = verify_output

if __name__ == "__main__":
    raise SystemExit(module.main())
