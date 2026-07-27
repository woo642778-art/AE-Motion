#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import plistlib
import struct
import tempfile
from argparse import Namespace
from pathlib import Path
import unittest
import zipfile

SCRIPT = Path(__file__).with_name("package-ui272-ipa.py")
spec = importlib.util.spec_from_file_location("package_ui272", SCRIPT)
module = importlib.util.module_from_spec(spec)
assert spec.loader
spec.loader.exec_module(module)

BASE_IPA = Path("/mnt/data/AE Motion 2.7(2).ipa")


def make_ui_framework(root: Path) -> Path:
    framework = root / module.UI_FRAMEWORK_NAME
    framework.mkdir()
    first = 512
    segment_size = 72 + 80
    segment = bytearray(segment_size)
    struct.pack_into("<II", segment, 0, 0x19, segment_size)
    segment[8:14] = b"__TEXT"
    struct.pack_into("<QQQQiiII", segment, 24, 0, 4096, 0, 4096, 5, 5, 1, 0)
    section = 72
    segment[section:section + 6] = b"__text"
    segment[section + 16:section + 22] = b"__TEXT"
    struct.pack_into("<QQIIIIIIII", segment, section + 32, 4096, 128, first, 2, 0, 0, 0, 0, 0, 0)
    data = bytearray(first + 128)
    struct.pack_into("<IiiIIIII", data, 0, 0xFEEDFACF, 0x0100000C, 0, 6, 1, len(segment), 0, 0)
    data[32:32 + len(segment)] = segment
    install_name = module.UI_LOAD_PATH.encode() + b"\0"
    data[first:first + len(install_name)] = install_name
    executable = framework / module.UI_EXECUTABLE_NAME
    executable.write_bytes(data)
    executable.chmod(0o755)
    info = {
        "CFBundleExecutable": module.UI_EXECUTABLE_NAME,
        "CFBundleIdentifier": "ae-motion-extensions.AEMotionUI272",
        "CFBundleShortVersionString": module.MARKETING_VERSION,
        "CFBundleVersion": str(module.BUILD_NUMBER),
        "CFBundlePackageType": "FMWK",
    }
    (framework / "Info.plist").write_bytes(plistlib.dumps(info, fmt=plistlib.FMT_XML, sort_keys=True))
    return framework


class PackageUI272Tests(unittest.TestCase):
    def test_preservation_gate_rejects_an_unexpected_change(self) -> None:
        before = {"untouched.bin": "aaa", "Info.plist": "bbb"}
        after = {"untouched.bin": "changed", "Info.plist": "new"}
        with self.assertRaisesRegex(module.PackageError, "unexpected baseline file change"):
            module.verify_preservation(before, after, [])

    def test_resolves_a_nested_framework_artifact(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            framework = make_ui_framework(root)
            inner = root / "inner.zip"
            with zipfile.ZipFile(inner, "w", zipfile.ZIP_DEFLATED) as archive:
                for path in framework.rglob("*"):
                    if path.is_file():
                        archive.write(path, path.relative_to(root))
            outer = root / "outer.zip"
            with zipfile.ZipFile(outer, "w", zipfile.ZIP_DEFLATED) as archive:
                archive.write(inner, "artifact/AEMotionUI272-framework.zip")
            workspace = root / "workspace"
            workspace.mkdir()
            resolved = module.resolve_ui_framework(outer, workspace)
            self.assertEqual(resolved.name, module.UI_FRAMEWORK_NAME)
            self.assertTrue((resolved / module.UI_EXECUTABLE_NAME).is_file())

    @unittest.skipUnless(BASE_IPA.is_file(), "user baseline IPA is unavailable")
    def test_packages_real_baseline_without_replacing_existing_extension(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            framework = make_ui_framework(root)
            output = root / "candidate.ipa"
            module.package(Namespace(
                base_ipa=BASE_IPA,
                ui_framework=framework,
                output=output,
                source_commit="test",
            ))
            report = json.loads(Path(str(output) + ".verification.json").read_text())
            self.assertTrue(report["hostExecutable"]["sectionBytesUnchanged"])
            self.assertFalse(report["physicalDeviceQualified"])
            with zipfile.ZipFile(output) as archive:
                names = set(archive.namelist())
                self.assertFalse(any("AEMotionLegacy" in name for name in names))
                prefix = "Payload/AlightMotion.app/"
                self.assertIn(
                    prefix + f"Frameworks/{module.UI_FRAMEWORK_NAME}/{module.UI_EXECUTABLE_NAME}",
                    names,
                )
                manifest = json.loads(archive.read(prefix + module.MANIFEST_NAME))
                self.assertEqual(manifest["integration"], "separate-signed-framework-explicit-load-command")
                self.assertTrue(manifest["existingExtensionPreserved"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
