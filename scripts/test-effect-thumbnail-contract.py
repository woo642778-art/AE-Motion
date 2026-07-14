#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
from pathlib import Path
import struct
import tempfile
import unittest
import sys

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("thumbnail_validator", ROOT / "scripts/validate-effect-thumbnails.py")
validator = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
sys.modules[SPEC.name] = validator
SPEC.loader.exec_module(validator)


def write_png_header(path: Path, width: int, height: int) -> None:
    path.write_bytes(
        validator.PNG_SIGNATURE
        + struct.pack(">I", 13)
        + b"IHDR"
        + struct.pack(">II", width, height)
        + b"\x08\x06\x00\x00\x00"
    )


class ThumbnailContractTests(unittest.TestCase):
    def test_bcc_descriptor_declares_exact_thumbnail(self) -> None:
        text = (ROOT / "Effects/v2.2/bccedgeglow.xml").read_text(encoding="utf-8")
        self.assertIn('thumb="thumb/bccedgeglow.png"', text)

    def test_missing_or_wrong_case_asset_fails(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            app = Path(raw) / "App.app"
            effects = app / "BuiltinEffects"
            effects.mkdir(parents=True)
            (effects / "bccedgeglow.xml").write_text(
                '<effect id="com.alightcreative.effects.bccedgeglow" thumb="thumb/bccedgeglow.png"/>',
                encoding="utf-8",
            )
            (effects / "thumb").mkdir()
            write_png_header(effects / "thumb/BCCEdgeGlow.png", 64, 64)
            result = validator.validate_thumbnail_contract(app)
            self.assertFalse(result["valid"])
            self.assertEqual(result["errors"][0]["code"], "missing_case_sensitive_asset")

    def test_valid_png_dimensions_pass(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            app = Path(raw) / "App.app"
            effects = app / "BuiltinEffects"
            effects.mkdir(parents=True)
            (effects / "fx.xml").write_text(
                '<effect id="com.test.fx" thumb="thumb/fx.png"/>', encoding="utf-8"
            )
            (effects / "thumb").mkdir()
            write_png_header(effects / "thumb/fx.png", 96, 54)
            result = validator.validate_thumbnail_contract(app)
            self.assertTrue(result["valid"])
            self.assertEqual(result["assetRoot"], "BuiltinEffects")
            self.assertEqual(result["checked"][0]["width"], 96)
            self.assertEqual(result["checked"][0]["height"], 54)

    def test_app_root_asset_does_not_satisfy_descriptor(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            app = Path(raw) / "App.app"
            effects = app / "BuiltinEffects"
            effects.mkdir(parents=True)
            (effects / "fx.xml").write_text(
                '<effect id="com.test.fx" thumb="thumb/fx.png"/>', encoding="utf-8"
            )
            (app / "thumb").mkdir()
            write_png_header(app / "thumb/fx.png", 96, 54)
            result = validator.validate_thumbnail_contract(app)
            self.assertFalse(result["valid"])

    def test_unsafe_relative_path_fails(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            app = Path(raw) / "App.app"
            (app / "BuiltinEffects").mkdir(parents=True)
            (app / "BuiltinEffects/fx.xml").write_text(
                '<effect id="com.test.fx" thumb="../outside.png"/>', encoding="utf-8"
            )
            result = validator.validate_thumbnail_contract(app)
            self.assertFalse(result["valid"])
            self.assertEqual(result["errors"][0]["code"], "unsafe_thumbnail_path")


if __name__ == "__main__":
    unittest.main()
