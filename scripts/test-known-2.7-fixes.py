#!/usr/bin/env python3
from __future__ import annotations

import hashlib
from pathlib import Path
import sys
import unittest
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parent))
from known_2_7_fixes import (  # noqa: E402
    BASE_FRAMEWORK_SHA256,
    BASE_INFO_PLIST_SHA256,
    BASE_PROMOTION_DYLIB_SHA256,
    PATCHED_FRAMEWORK_SHA256,
    PATCHED_INFO_PLIST_SHA256,
    PATCHED_PROMOTION_DYLIB_SHA256,
    patch_extension_framework,
    patch_info_plist,
    patch_promotion_dylib,
)

BASE_IPA = Path("/mnt/data/AE Motion 2.7(2).ipa")
VERIFIED_IPA = Path("/mnt/data/AE Motion 2.7 Final-unsigned.ipa")


class Known27FixTests(unittest.TestCase):
    @unittest.skipUnless(BASE_IPA.is_file() and VERIFIED_IPA.is_file(), "reference IPAs are unavailable")
    def test_exactly_reproduces_verified_three_file_patch(self) -> None:
        with zipfile.ZipFile(BASE_IPA) as base, zipfile.ZipFile(VERIFIED_IPA) as verified:
            items = (
                (
                    "Payload/AlightMotion.app/Frameworks/AEMotionExtensionsHost.framework/AEMotionExtensionsHost",
                    patch_extension_framework,
                    BASE_FRAMEWORK_SHA256,
                    PATCHED_FRAMEWORK_SHA256,
                ),
                (
                    "Payload/AlightMotion.app/Frameworks/AlightMotion.dylib",
                    patch_promotion_dylib,
                    BASE_PROMOTION_DYLIB_SHA256,
                    PATCHED_PROMOTION_DYLIB_SHA256,
                ),
                (
                    "Payload/AlightMotion.app/Info.plist",
                    patch_info_plist,
                    BASE_INFO_PLIST_SHA256,
                    PATCHED_INFO_PLIST_SHA256,
                ),
            )
            for path, patch, base_hash, final_hash in items:
                original = base.read(path)
                expected = verified.read(path)
                self.assertEqual(hashlib.sha256(original).hexdigest(), base_hash)
                result = patch(original)
                self.assertEqual(result, expected)
                self.assertEqual(hashlib.sha256(result).hexdigest(), final_hash)
                self.assertEqual(patch(result), result)

    def test_rejects_unknown_binaries(self) -> None:
        with self.assertRaises(Exception):
            patch_extension_framework(b"not the baseline")
        with self.assertRaises(Exception):
            patch_promotion_dylib(b"not the baseline")
        with self.assertRaises(Exception):
            patch_info_plist(b"not the baseline")


if __name__ == "__main__":
    unittest.main(verbosity=2)
