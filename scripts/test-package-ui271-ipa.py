#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import os
import plistlib
import stat
import tempfile
import unittest
import zipfile
from argparse import Namespace
from pathlib import Path

SCRIPT = Path(__file__).with_name("package-ui271-ipa.py")
spec = importlib.util.spec_from_file_location("package_ui271", SCRIPT)
module = importlib.util.module_from_spec(spec)
assert spec.loader
spec.loader.exec_module(module)


def write_macho(path: Path, payload: bytes) -> None:
    path.write_bytes(module.MACHO_64_MAGIC + b"\x00" * 64 + payload + b"\x00" * 64)
    os.chmod(path, 0o755)


def zip_tree(root: Path, output: Path) -> None:
    with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(root.rglob("*")):
            if path.is_file():
                info = zipfile.ZipInfo(path.relative_to(root).as_posix())
                info.external_attr = (stat.S_IFREG | stat.S_IMODE(path.stat().st_mode)) << 16
                archive.writestr(info, path.read_bytes())


class PackageUI271Tests(unittest.TestCase):
    def make_fixture(self, root: Path) -> tuple[Path, Path]:
        app = root / "base" / "Payload" / "AlightMotion.app"
        framework = app / "Frameworks" / module.FRAMEWORK_NAME
        framework.mkdir(parents=True)
        with (app / "Info.plist").open("wb") as stream:
            plistlib.dump({
                "CFBundleIdentifier": "com.alightcreative.motion",
                "CFBundleDisplayName": "AE Motion",
                "CFBundleShortVersionString": "6.2.42",
                "CFBundleVersion": "838",
                "AEMotionReleaseVersion": "2.7",
            }, stream)
        with (framework / "Info.plist").open("wb") as stream:
            plistlib.dump({
                "CFBundleExecutable": module.FRAMEWORK_EXECUTABLE,
                "CFBundleIdentifier": "ae-motion-extensions.AEMotionExtensionsHost",
                "CFBundleShortVersionString": "2.7",
                "CFBundleVersion": "270",
            }, stream)
        original = framework / module.FRAMEWORK_EXECUTABLE
        write_macho(original, module.OLD_INSTALL_NAME)
        signature = app / "_CodeSignature"
        signature.mkdir()
        (signature / "CodeResources").write_text("stale", encoding="utf-8")
        (app / "embedded.mobileprovision").write_text("stale", encoding="utf-8")
        base_ipa = root / "base.ipa"
        zip_tree(root / "base", base_ipa)

        wrapper = root / module.FRAMEWORK_NAME
        wrapper.mkdir()
        write_macho(wrapper / module.FRAMEWORK_EXECUTABLE, b"UI271_WRAPPER")
        with (wrapper / "Info.plist").open("wb") as stream:
            plistlib.dump({
                "CFBundleExecutable": module.FRAMEWORK_EXECUTABLE,
                "CFBundleIdentifier": "ae-motion-extensions.AEMotionExtensionsHost",
            }, stream)
        return base_ipa, wrapper

    def test_install_name_patch_is_in_place(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            binary = Path(temporary) / "legacy"
            write_macho(binary, module.OLD_INSTALL_NAME)
            original_size = binary.stat().st_size
            module.patch_legacy_install_name(binary)
            data = binary.read_bytes()
            self.assertEqual(binary.stat().st_size, original_size)
            self.assertNotIn(module.OLD_INSTALL_NAME, data)
            self.assertIn(module.LEGACY_INSTALL_NAME, data)

    def test_packages_wrapper_legacy_version_and_unsigned_state(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            base_ipa, wrapper = self.make_fixture(root)
            output = root / "AE Motion 2.7.1-unsigned.ipa"
            module.package(Namespace(
                base_ipa=base_ipa,
                wrapper_framework=wrapper,
                output=output,
                source_commit="abc123",
            ))
            self.assertTrue(output.is_file())
            with zipfile.ZipFile(output) as archive:
                self.assertIsNone(archive.testzip())
                prefix = "Payload/AlightMotion.app/"
                framework_prefix = prefix + f"Frameworks/{module.FRAMEWORK_NAME}/"
                names = set(archive.namelist())
                self.assertIn(framework_prefix + module.FRAMEWORK_EXECUTABLE, names)
                self.assertIn(framework_prefix + module.LEGACY_EXECUTABLE, names)
                self.assertNotIn(prefix + "embedded.mobileprovision", names)
                self.assertFalse(any("_CodeSignature" in name for name in names))
                app_plist = plistlib.loads(archive.read(prefix + "Info.plist"))
                self.assertEqual(app_plist["AEMotionReleaseVersion"], "2.7.1")
                self.assertEqual(app_plist["AEMotionReleaseBuild"], 839)
                self.assertEqual(app_plist["CFBundleVersion"], "839")
                manifest = json.loads(archive.read(prefix + "AEMotionV271Build.json"))
                self.assertEqual(manifest["release"], "AE Motion 2.7.1")
                self.assertEqual(manifest["build"], 839)
                self.assertFalse(manifest["physicalDeviceQualified"])
                legacy = archive.read(framework_prefix + module.LEGACY_EXECUTABLE)
                wrapper_data = archive.read(framework_prefix + module.FRAMEWORK_EXECUTABLE)
                self.assertIn(module.LEGACY_INSTALL_NAME, legacy)
                self.assertIn(b"UI271_WRAPPER", wrapper_data)

    def test_rejects_base_binary_without_exact_original_install_name(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            binary = Path(temporary) / "legacy"
            write_macho(binary, b"wrong-install-name")
            with self.assertRaisesRegex(RuntimeError, "exactly one"):
                module.patch_legacy_install_name(binary)


if __name__ == "__main__":
    unittest.main(verbosity=2)
