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

MARKETING_VERSION = "2.7.1"
BUILD_NUMBER = 839
FRAMEWORK_NAME = "AEMotionExtensionsHost.framework"
FRAMEWORK_EXECUTABLE = "AEMotionExtensionsHost"
LEGACY_EXECUTABLE = "AEMotionLegacy"
OLD_INSTALL_NAME = b"@rpath/AEMotionExtensionsHost.framework/AEMotionExtensionsHost\x00"
LEGACY_INSTALL_NAME = b"@rpath/AEMotionExtensionsHost.framework/AEMotionLegacy\x00"
MACHO_64_MAGIC = b"\xcf\xfa\xed\xfe"
FIXED_ZIP_TIME = (2026, 7, 26, 0, 0, 0)


def sha256(path: Path) -> str:
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
        raise RuntimeError(f"Expected exactly one app bundle, found {len(apps)}")
    return apps[0]


def resolve_wrapper_framework(source: Path, workspace: Path) -> Path:
    if source.is_dir() and source.name == FRAMEWORK_NAME:
        return source
    if source.is_file() and source.suffix.lower() == ".zip":
        extracted = workspace / "wrapper-artifact"
        extracted.mkdir(parents=True, exist_ok=True)
        extract_zip_preserving_modes(source, extracted)
        matches = sorted(extracted.rglob(FRAMEWORK_NAME))
        if len(matches) != 1:
            raise RuntimeError(f"Expected one wrapper framework in artifact, found {len(matches)}")
        return matches[0]
    raise RuntimeError("--wrapper-framework must be an AEMotionExtensionsHost.framework directory or ZIP artifact")


def require_macho(path: Path, label: str) -> None:
    with path.open("rb") as stream:
        magic = stream.read(4)
    if magic != MACHO_64_MAGIC:
        raise RuntimeError(f"{label} is not a thin 64-bit Mach-O executable: {path}")


def patch_legacy_install_name(path: Path) -> None:
    if len(LEGACY_INSTALL_NAME) > len(OLD_INSTALL_NAME):
        raise RuntimeError("Legacy install name does not fit the existing Mach-O command")
    data = path.read_bytes()
    count = data.count(OLD_INSTALL_NAME)
    if count != 1:
        raise RuntimeError(f"Expected exactly one framework LC_ID string, found {count}")
    replacement = LEGACY_INSTALL_NAME + b"\x00" * (len(OLD_INSTALL_NAME) - len(LEGACY_INSTALL_NAME))
    patched = data.replace(OLD_INSTALL_NAME, replacement, 1)
    if len(patched) != len(data):
        raise RuntimeError("Install-name patch changed the legacy binary size")
    path.write_bytes(patched)
    if OLD_INSTALL_NAME in patched or LEGACY_INSTALL_NAME not in patched:
        raise RuntimeError("Legacy install-name verification failed")


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


def merge_wrapper_framework(wrapper: Path, destination: Path) -> None:
    wrapper_executable = wrapper / FRAMEWORK_EXECUTABLE
    require_macho(wrapper_executable, "Wrapper framework executable")
    destination_executable = destination / FRAMEWORK_EXECUTABLE
    shutil.copy2(wrapper_executable, destination_executable)
    os.chmod(destination_executable, 0o755)

    for item in wrapper.iterdir():
        if item.name in {FRAMEWORK_EXECUTABLE, "Info.plist", "_CodeSignature"}:
            continue
        target = destination / item.name
        if target.exists():
            if target.is_dir():
                shutil.rmtree(target)
            else:
                target.unlink()
        if item.is_dir():
            shutil.copytree(item, target)
        else:
            shutil.copy2(item, target)


def update_plists(app: Path, framework: Path) -> None:
    app_plist_path = app / "Info.plist"
    with app_plist_path.open("rb") as stream:
        app_plist = plistlib.load(stream)
    app_plist["AEMotionReleaseVersion"] = MARKETING_VERSION
    app_plist["AEMotionReleaseBuild"] = BUILD_NUMBER
    app_plist["AEMotionReleaseDisplayVersion"] = f"{MARKETING_VERSION} ({BUILD_NUMBER})"
    app_plist["CFBundleVersion"] = str(BUILD_NUMBER)
    with app_plist_path.open("wb") as stream:
        plistlib.dump(app_plist, stream, fmt=plistlib.FMT_BINARY, sort_keys=True)

    framework_plist_path = framework / "Info.plist"
    with framework_plist_path.open("rb") as stream:
        framework_plist = plistlib.load(stream)
    framework_plist["CFBundleExecutable"] = FRAMEWORK_EXECUTABLE
    framework_plist["CFBundleShortVersionString"] = MARKETING_VERSION
    framework_plist["CFBundleVersion"] = str(BUILD_NUMBER)
    framework_plist["AEMotionLegacyExecutable"] = LEGACY_EXECUTABLE
    with framework_plist_path.open("wb") as stream:
        plistlib.dump(framework_plist, stream, fmt=plistlib.FMT_BINARY, sort_keys=True)


def write_release_manifest(app: Path, *, source_commit: str, base_ipa_hash: str, legacy_hash: str, wrapper_hash: str) -> Path:
    manifest_path = app / "AEMotionV271Build.json"
    manifest = {
        "schemaVersion": 1,
        "release": f"AE Motion {MARKETING_VERSION}",
        "build": BUILD_NUMBER,
        "sourceCommit": source_commit,
        "sourceBranch": "fix/home-shell-ui-restoration",
        "baseIPA_SHA256": base_ipa_hash,
        "legacyFrameworkOriginalSHA256": legacy_hash,
        "wrapperFrameworkSHA256": wrapper_hash,
        "legacyExecutable": LEGACY_EXECUTABLE,
        "homeShellSourceControlled": True,
        "singleShellNavigationOwner": True,
        "homeProjectsTemplatesUIRestored": True,
        "nativeAmbientField": True,
        "nativeSpotlightCards": True,
        "reduceMotionFallback": True,
        "reduceTransparencyFallback": True,
        "editingAssetLibraryBundled": False,
        "physicalDeviceQualified": False,
        "simulatorInteractionQualified": False,
        "unsignedCandidate": True,
    }
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return manifest_path


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
            raise RuntimeError(f"ZIP CRC failed at {bad}")
        names = set(archive.namelist())
        apps = sorted({name.split("/")[1] for name in names if name.startswith("Payload/") and ".app/" in name})
        if len(apps) != 1:
            raise RuntimeError("Packaged IPA does not contain exactly one app")
        app_prefix = f"Payload/{apps[0]}/"
        framework_prefix = app_prefix + f"Frameworks/{FRAMEWORK_NAME}/"
        required = {
            framework_prefix + FRAMEWORK_EXECUTABLE,
            framework_prefix + LEGACY_EXECUTABLE,
            app_prefix + "AEMotionV271Build.json",
            app_prefix + "Info.plist",
        }
        missing = sorted(required - names)
        if missing:
            raise RuntimeError("Missing packaged files: " + ", ".join(missing))
        if any("_CodeSignature/" in name or name.endswith("embedded.mobileprovision") for name in names):
            raise RuntimeError("Signing material remains in packaged IPA")
        app_plist = plistlib.loads(archive.read(app_prefix + "Info.plist"))
        if app_plist.get("AEMotionReleaseVersion") != MARKETING_VERSION:
            raise RuntimeError("Packaged AE Motion release version is incorrect")
        if int(app_plist.get("AEMotionReleaseBuild", -1)) != BUILD_NUMBER:
            raise RuntimeError("Packaged AE Motion build number is incorrect")
        legacy_data = archive.read(framework_prefix + LEGACY_EXECUTABLE)
        if OLD_INSTALL_NAME in legacy_data or LEGACY_INSTALL_NAME not in legacy_data:
            raise RuntimeError("Packaged legacy install name is incorrect")
    return {
        "zipCRC": "pass",
        "marketingVersion": MARKETING_VERSION,
        "buildNumber": BUILD_NUMBER,
        "requiredFiles": "pass",
        "signingMaterialRemoved": True,
    }


def package(args: argparse.Namespace) -> tuple[Path, Path, Path]:
    base_ipa = args.base_ipa.resolve()
    wrapper_source = args.wrapper_framework.resolve()
    output = args.output.resolve()
    if not base_ipa.is_file():
        raise RuntimeError(f"Base IPA not found: {base_ipa}")

    with tempfile.TemporaryDirectory(prefix="aemotion-ui271-") as temporary:
        workspace = Path(temporary)
        unpacked = workspace / "ipa"
        unpacked.mkdir()
        extract_zip_preserving_modes(base_ipa, unpacked)
        app = find_app(unpacked)
        framework = app / "Frameworks" / FRAMEWORK_NAME
        if not framework.is_dir():
            raise RuntimeError(f"Base IPA is missing {FRAMEWORK_NAME}")
        original = framework / FRAMEWORK_EXECUTABLE
        require_macho(original, "Base 2.7 framework executable")
        legacy_original_hash = sha256(original)

        wrapper = resolve_wrapper_framework(wrapper_source, workspace)
        wrapper_executable = wrapper / FRAMEWORK_EXECUTABLE
        wrapper_hash = sha256(wrapper_executable)

        legacy = framework / LEGACY_EXECUTABLE
        if legacy.exists():
            legacy.unlink()
        shutil.copy2(original, legacy)
        os.chmod(legacy, 0o755)
        patch_legacy_install_name(legacy)
        merge_wrapper_framework(wrapper, framework)
        update_plists(app, framework)
        removed_signing = remove_signing_material(app)
        manifest_path = write_release_manifest(
            app,
            source_commit=args.source_commit,
            base_ipa_hash=sha256(base_ipa),
            legacy_hash=legacy_original_hash,
            wrapper_hash=wrapper_hash,
        )
        deterministic_zip(unpacked, output)

        verification = verify_output(output)
        verification.update({
            "baseIPA": str(base_ipa),
            "baseIPA_SHA256": sha256(base_ipa),
            "outputIPA": str(output),
            "outputIPA_SHA256": sha256(output),
            "legacyOriginalSHA256": legacy_original_hash,
            "legacyPatchedSHA256": sha256(legacy),
            "wrapperSHA256": wrapper_hash,
            "removedSigningEntries": removed_signing,
            "releaseManifest": manifest_path.name,
            "physicalDeviceQualified": False,
            "simulatorInteractionQualified": False,
        })

    checksum_path = output.with_suffix(output.suffix + ".sha256")
    checksum_path.write_text(f"{sha256(output)}  {output.name}\n", encoding="utf-8")
    report_path = output.with_suffix(output.suffix + ".verification.json")
    report_path.write_text(json.dumps(verification, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return output, checksum_path, report_path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Package the AE Motion 2.7.1 unsigned UI wrapper IPA")
    parser.add_argument("--base-ipa", type=Path, required=True)
    parser.add_argument("--wrapper-framework", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--source-commit", default="uncommitted")
    return parser.parse_args()


def main() -> int:
    try:
        output, checksum, report = package(parse_args())
    except Exception as error:
        print(f"ERROR: {error}")
        return 1
    print(output)
    print(checksum)
    print(report)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
