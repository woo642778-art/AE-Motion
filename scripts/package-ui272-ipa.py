#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import os
import plistlib
import shutil
import stat
import tempfile
import zipfile
from pathlib import Path

from known_2_7_fixes import (
    PATCHED_FRAMEWORK_SHA256,
    PATCHED_PROMOTION_DYLIB_SHA256,
    patch_extension_framework,
    patch_info_plist,
    patch_promotion_dylib,
)
from macho_load_command import append_load_dylib, inspect_macho

BASE_IPA_SHA256 = "f72053a38a64ea2dac48e18d248d1b279755e24e0318724015b4fd9356090a6d"
MARKETING_VERSION = "2.7.2"
BUILD_NUMBER = 840
UI_FRAMEWORK_NAME = "AEMotionUI272.framework"
UI_EXECUTABLE_NAME = "AEMotionUI272"
UI_LOAD_PATH = "@rpath/AEMotionUI272.framework/AEMotionUI272"
EXISTING_EXTENSION_LOAD_PATH = "@rpath/AEMotionExtensionsHost.framework/AEMotionExtensionsHost"
FIXED_ZIP_TIME = (2026, 7, 27, 0, 0, 0)

MAIN_RELATIVE = Path("AlightMotion")
PROMOTION_RELATIVE = Path("Frameworks/AlightMotion.dylib")
EXTENSION_RELATIVE = Path("Frameworks/AEMotionExtensionsHost.framework/AEMotionExtensionsHost")
INFO_RELATIVE = Path("Info.plist")
MANIFEST_NAME = "AEMotionV272Build.json"


class PackageError(RuntimeError):
    pass


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def extract_zip_preserving_modes(archive: Path, destination: Path) -> None:
    with zipfile.ZipFile(archive) as source:
        for info in source.infolist():
            target = destination / info.filename
            if info.is_dir():
                target.mkdir(parents=True, exist_ok=True)
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            with source.open(info) as input_stream, target.open("wb") as output_stream:
                shutil.copyfileobj(input_stream, output_stream)
            mode = (info.external_attr >> 16) & 0xFFFF
            if mode:
                os.chmod(target, stat.S_IMODE(mode))


def find_app(root: Path) -> Path:
    apps = sorted((root / "Payload").glob("*.app"))
    if len(apps) != 1:
        raise PackageError(f"expected exactly one app bundle, found {len(apps)}")
    return apps[0]


def resolve_ui_framework(source: Path, workspace: Path) -> Path:
    if source.is_dir() and source.name == UI_FRAMEWORK_NAME:
        return source
    if not source.is_file() or source.suffix.lower() != ".zip":
        raise PackageError("--ui-framework must be AEMotionUI272.framework or a ZIP artifact")
    extraction = workspace / "ui-artifact"
    extraction.mkdir(parents=True, exist_ok=True)
    extract_zip_preserving_modes(source, extraction)
    matches = sorted(extraction.rglob(UI_FRAMEWORK_NAME))
    if len(matches) == 1:
        return matches[0]
    for nested in sorted(extraction.rglob("*.zip")):
        nested_root = extraction / ("nested-" + hashlib.sha256(str(nested).encode()).hexdigest()[:12])
        nested_root.mkdir()
        extract_zip_preserving_modes(nested, nested_root)
        matches.extend(nested_root.rglob(UI_FRAMEWORK_NAME))
    unique = sorted({path.resolve() for path in matches})
    if len(unique) != 1:
        raise PackageError(f"expected one {UI_FRAMEWORK_NAME}, found {len(unique)}")
    return unique[0]


def verify_ui_framework(framework: Path) -> dict[str, str]:
    executable = framework / UI_EXECUTABLE_NAME
    info_path = framework / "Info.plist"
    if not executable.is_file() or not info_path.is_file():
        raise PackageError("UI framework is missing its executable or Info.plist")
    info = inspect_macho(executable.read_bytes())
    plist = plistlib.loads(info_path.read_bytes())
    if plist.get("CFBundleExecutable") != UI_EXECUTABLE_NAME:
        raise PackageError("UI framework CFBundleExecutable is incorrect")
    if plist.get("CFBundleShortVersionString") != MARKETING_VERSION:
        raise PackageError("UI framework marketing version is incorrect")
    if str(plist.get("CFBundleVersion")) != str(BUILD_NUMBER):
        raise PackageError("UI framework build number is incorrect")
    data = executable.read_bytes()
    if UI_LOAD_PATH.encode() not in data:
        raise PackageError("UI framework install name is missing")
    for forbidden in (b"AEMotionLegacy", b"LegacyFrameworkLoader"):
        if forbidden in data:
            raise PackageError(f"UI framework contains forbidden legacy loader token: {forbidden!r}")
    return {
        "executableSHA256": sha256_file(executable),
        "infoPlistSHA256": sha256_file(info_path),
        "firstSectionOffset": str(info.first_section_offset),
    }


def remove_signing_material(app: Path) -> list[str]:
    removed: list[str] = []
    for directory in sorted(app.rglob("_CodeSignature"), reverse=True):
        if directory.is_dir():
            removed.append(str(directory.relative_to(app)))
            shutil.rmtree(directory)
    for name in ("embedded.mobileprovision", "CodeResources"):
        for item in sorted(app.rglob(name)):
            if item.is_file():
                removed.append(str(item.relative_to(app)))
                item.unlink()
    return sorted(set(removed))


def file_inventory(app: Path) -> dict[str, str]:
    return {
        path.relative_to(app).as_posix(): sha256_file(path)
        for path in sorted(app.rglob("*"))
        if path.is_file()
    }


def apply_verified_2_7_fixes(app: Path) -> dict[str, str]:
    extension = app / EXTENSION_RELATIVE
    promotion = app / PROMOTION_RELATIVE
    info = app / INFO_RELATIVE
    extension.write_bytes(patch_extension_framework(extension.read_bytes()))
    promotion.write_bytes(patch_promotion_dylib(promotion.read_bytes()))
    info.write_bytes(patch_info_plist(info.read_bytes()))
    if sha256_file(extension) != PATCHED_FRAMEWORK_SHA256:
        raise PackageError("verified extension patch was not preserved")
    if sha256_file(promotion) != PATCHED_PROMOTION_DYLIB_SHA256:
        raise PackageError("verified promotion patch was not preserved")
    return {
        EXTENSION_RELATIVE.as_posix(): sha256_file(extension),
        PROMOTION_RELATIVE.as_posix(): sha256_file(promotion),
        INFO_RELATIVE.as_posix(): sha256_file(info),
    }


def patch_main_executable(app: Path) -> dict[str, object]:
    path = app / MAIN_RELATIVE
    original = path.read_bytes()
    before = inspect_macho(original)
    if before.dylib_paths.count(EXISTING_EXTENSION_LOAD_PATH) != 1:
        raise PackageError("existing AE Motion extension load command is missing or duplicated")
    patched = append_load_dylib(original, UI_LOAD_PATH)
    after = inspect_macho(patched)
    if after.dylib_paths.count(UI_LOAD_PATH) != 1:
        raise PackageError("UI framework load command verification failed")
    if after.dylib_paths.index(EXISTING_EXTENSION_LOAD_PATH) > after.dylib_paths.index(UI_LOAD_PATH):
        raise PackageError("UI framework would load before the existing extension framework")
    if patched[before.first_section_offset:] != original[before.first_section_offset:]:
        raise PackageError("host executable section bytes changed")
    path.write_bytes(patched)
    os.chmod(path, 0o755)
    return {
        "originalSHA256": sha256_bytes(original),
        "patchedSHA256": sha256_bytes(patched),
        "firstSectionOffset": before.first_section_offset,
        "originalNcmds": before.ncmds,
        "patchedNcmds": after.ncmds,
        "sectionBytesUnchanged": True,
    }


def update_release_metadata(app: Path) -> None:
    path = app / INFO_RELATIVE
    value = plistlib.loads(path.read_bytes())
    value["AEMotionReleaseVersion"] = MARKETING_VERSION
    value["AEMotionReleaseBuild"] = BUILD_NUMBER
    value["AEMotionReleaseDisplayVersion"] = f"{MARKETING_VERSION} ({BUILD_NUMBER})"
    value["AEMotionUIFramework"] = UI_FRAMEWORK_NAME
    value["CFBundleVersion"] = str(BUILD_NUMBER)
    path.write_bytes(plistlib.dumps(value, fmt=plistlib.FMT_XML, sort_keys=True))


def copy_ui_framework(source: Path, app: Path) -> Path:
    destination = app / "Frameworks" / UI_FRAMEWORK_NAME
    if destination.exists():
        shutil.rmtree(destination)
    shutil.copytree(source, destination, copy_function=shutil.copy2)
    executable = destination / UI_EXECUTABLE_NAME
    os.chmod(executable, 0o755)
    return destination


def verify_preservation(before: dict[str, str], after: dict[str, str], removed_signing: list[str]) -> None:
    mutable = {
        MAIN_RELATIVE.as_posix(),
        PROMOTION_RELATIVE.as_posix(),
        EXTENSION_RELATIVE.as_posix(),
        INFO_RELATIVE.as_posix(),
    }
    removed_prefixes = tuple(entry.rstrip("/") + "/" for entry in removed_signing if entry.endswith("_CodeSignature"))
    removed_exact = set(removed_signing)
    for path, digest in before.items():
        if path in mutable or path in removed_exact or path.startswith(removed_prefixes):
            continue
        actual = after.get(path)
        if actual != digest:
            raise PackageError(f"unexpected baseline file change: {path}")
    for path in after:
        if path in before:
            continue
        if not (path.startswith(f"Frameworks/{UI_FRAMEWORK_NAME}/") or path == MANIFEST_NAME):
            raise PackageError(f"unexpected added file: {path}")


def write_manifest(app: Path, *, source_commit: str, base_hash: str, framework_report: dict[str, str], main_report: dict[str, object]) -> Path:
    path = app / MANIFEST_NAME
    value = {
        "schemaVersion": 2,
        "release": f"AE Motion {MARKETING_VERSION}",
        "build": BUILD_NUMBER,
        "sourceBranch": "fix/2.7.2-recovery",
        "sourceCommit": source_commit,
        "baseIPA_SHA256": base_hash,
        "integration": "separate-signed-framework-explicit-load-command",
        "existingExtensionPreserved": True,
        "verified27CompatibilityPatchesApplied": True,
        "uiFramework": framework_report,
        "hostExecutable": main_report,
        "containsAEMotionLegacy": False,
        "physicalDeviceQualified": False,
        "unsignedCandidate": True,
    }
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return path


def deterministic_zip(source_root: Path, output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in sorted(source_root.rglob("*"), key=lambda item: item.as_posix()):
            relative = path.relative_to(source_root).as_posix()
            if path.is_dir():
                info = zipfile.ZipInfo(relative.rstrip("/") + "/", FIXED_ZIP_TIME)
                info.external_attr = (stat.S_IFDIR | 0o755) << 16
                archive.writestr(info, b"")
                continue
            mode = stat.S_IMODE(path.stat().st_mode) or 0o644
            info = zipfile.ZipInfo(relative, FIXED_ZIP_TIME)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = (stat.S_IFREG | mode) << 16
            archive.writestr(info, path.read_bytes())


def verify_output(output: Path) -> dict[str, object]:
    with zipfile.ZipFile(output) as archive:
        bad = archive.testzip()
        if bad is not None:
            raise PackageError(f"ZIP CRC failed at {bad}")
        names = set(archive.namelist())
        apps = sorted({name.split("/")[1] for name in names if name.startswith("Payload/") and ".app/" in name})
        if len(apps) != 1:
            raise PackageError("output does not contain exactly one app")
        prefix = f"Payload/{apps[0]}/"
        required = {
            prefix + "AlightMotion",
            prefix + f"Frameworks/{UI_FRAMEWORK_NAME}/{UI_EXECUTABLE_NAME}",
            prefix + "Frameworks/AEMotionExtensionsHost.framework/AEMotionExtensionsHost",
            prefix + MANIFEST_NAME,
            prefix + "Info.plist",
        }
        missing = required - names
        if missing:
            raise PackageError("missing output files: " + ", ".join(sorted(missing)))
        if any("AEMotionLegacy" in name for name in names):
            raise PackageError("rejected AEMotionLegacy executable remains")
        if any("_CodeSignature/" in name or name.endswith("embedded.mobileprovision") for name in names):
            raise PackageError("signing material remains")
        main = archive.read(prefix + "AlightMotion")
        info = inspect_macho(main)
        if info.dylib_paths.count(UI_LOAD_PATH) != 1:
            raise PackageError("output UI load command is incorrect")
        if info.dylib_paths.count(EXISTING_EXTENSION_LOAD_PATH) != 1:
            raise PackageError("output existing extension load command is incorrect")
        extension = archive.read(prefix + "Frameworks/AEMotionExtensionsHost.framework/AEMotionExtensionsHost")
        promotion = archive.read(prefix + "Frameworks/AlightMotion.dylib")
        if sha256_bytes(extension) != PATCHED_FRAMEWORK_SHA256:
            raise PackageError("output extension patch hash is incorrect")
        if sha256_bytes(promotion) != PATCHED_PROMOTION_DYLIB_SHA256:
            raise PackageError("output promotion patch hash is incorrect")
        app_info = plistlib.loads(archive.read(prefix + "Info.plist"))
        if app_info.get("AEMotionReleaseVersion") != MARKETING_VERSION or int(app_info.get("AEMotionReleaseBuild", -1)) != BUILD_NUMBER:
            raise PackageError("output release metadata is incorrect")
        if app_info.get("@IPAdecryptBot") != "by https://t.me/aemotionios":
            raise PackageError("output Telegram metadata is incorrect")
    return {
        "zipCRC": "pass",
        "requiredFiles": "pass",
        "signingMaterialRemoved": True,
        "uiLoadCommandCount": 1,
        "existingExtensionLoadCommandCount": 1,
    }


def package(args: argparse.Namespace) -> tuple[Path, Path, Path]:
    base_ipa = args.base_ipa.resolve()
    ui_source = args.ui_framework.resolve()
    output = args.output.resolve()
    if not base_ipa.is_file():
        raise PackageError(f"baseline IPA not found: {base_ipa}")
    base_hash = sha256_file(base_ipa)
    if base_hash != BASE_IPA_SHA256:
        raise PackageError(f"baseline IPA SHA-256 mismatch: {base_hash}")

    with tempfile.TemporaryDirectory(prefix="aemotion-ui272-") as temporary:
        workspace = Path(temporary)
        unpacked = workspace / "ipa"
        unpacked.mkdir()
        extract_zip_preserving_modes(base_ipa, unpacked)
        app = find_app(unpacked)
        before = file_inventory(app)

        framework = resolve_ui_framework(ui_source, workspace)
        framework_report = verify_ui_framework(framework)
        apply_verified_2_7_fixes(app)
        main_report = patch_main_executable(app)
        copy_ui_framework(framework, app)
        update_release_metadata(app)
        removed_signing = remove_signing_material(app)
        manifest = write_manifest(
            app,
            source_commit=args.source_commit,
            base_hash=base_hash,
            framework_report=framework_report,
            main_report=main_report,
        )
        after = file_inventory(app)
        verify_preservation(before, after, removed_signing)
        deterministic_zip(unpacked, output)
        verification = verify_output(output)
        verification.update({
            "baseIPA": str(base_ipa),
            "baseIPA_SHA256": base_hash,
            "outputIPA": str(output),
            "outputIPA_SHA256": sha256_file(output),
            "uiFramework": framework_report,
            "hostExecutable": main_report,
            "removedSigningEntries": removed_signing,
            "manifest": manifest.name,
            "physicalDeviceQualified": False,
            "candidateOnly": True,
        })

    checksum = output.with_suffix(output.suffix + ".sha256")
    checksum.write_text(f"{sha256_file(output)}  {output.name}\n", encoding="utf-8")
    report = output.with_suffix(output.suffix + ".verification.json")
    report.write_text(json.dumps(verification, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return output, checksum, report


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Package AE Motion 2.7.2 recovery candidate")
    parser.add_argument("--base-ipa", type=Path, required=True)
    parser.add_argument("--ui-framework", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--source-commit", default="uncommitted")
    return parser.parse_args()


def main() -> int:
    try:
        paths = package(parse_args())
    except Exception as error:
        print(f"ERROR: {error}")
        return 1
    for path in paths:
        print(path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
