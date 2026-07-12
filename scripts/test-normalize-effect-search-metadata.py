#!/usr/bin/env python3
from __future__ import annotations

import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "normalize-effect-search-metadata.py"
FIXTURE = ROOT / "scripts" / "fixtures" / "bcc-lighting.xml"


class NormalizeEffectMetadataTests(unittest.TestCase):
    def test_bcc_aliases_and_supported_category_are_written_without_body_loss(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            effects = Path(temporary) / "BuiltinEffects"
            effects.mkdir()
            destination = effects / "bcc film glow.xml"
            destination.write_bytes(FIXTURE.read_bytes())

            completed = subprocess.run(
                ["python3", str(SCRIPT), str(effects)],
                check=True,
                capture_output=True,
                text=True,
            )
            output = destination.read_text(encoding="utf-8")

            self.assertIn("Normalized 1 of 1", completed.stdout)
            self.assertIn('category="drawing"', output)
            self.assertIn("bcc", output)
            self.assertIn("bbc", output)
            self.assertIn("borisfx", output)
            self.assertIn("continuum", output)
            self.assertNotIn(",com,", output)
            self.assertNotIn(",alightcreative,", output)
            self.assertIn('<spinner id="amount" default="1"/>', output)

    def test_second_run_is_idempotent(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            effects = Path(temporary) / "BuiltinEffects"
            effects.mkdir()
            destination = effects / "bcc film glow.xml"
            destination.write_bytes(FIXTURE.read_bytes())

            subprocess.run(["python3", str(SCRIPT), str(effects)], check=True)
            first = destination.read_bytes()
            second_run = subprocess.run(
                ["python3", str(SCRIPT), str(effects)],
                check=True,
                capture_output=True,
                text=True,
            )
            self.assertEqual(first, destination.read_bytes())
            self.assertIn("Normalized 0 of 1", second_run.stdout)


    def test_native_move_and_distortion_categories_are_restored_with_aliases(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            effects = Path(temporary) / "BuiltinEffects"
            effects.mkdir()
            move = effects / "move.xml"
            warp = effects / "warp.xml"
            move.write_text('<effect id="move.test" name="Move Test" category="move"><spinner id="x"/></effect>', encoding="utf-8")
            warp.write_text('<effect id="warp.test" name="Warp Test" category="distortion/warp"><spinner id="amount"/></effect>', encoding="utf-8")

            subprocess.run(["python3", str(SCRIPT), str(effects)], check=True)
            move_text = move.read_text(encoding="utf-8")
            warp_text = warp.read_text(encoding="utf-8")
            self.assertIn('category="transform"', move_text)
            self.assertIn('category="distort"', warp_text)
            for alias in ("move", "transform", "move/transform"):
                self.assertIn(alias, move_text)
            for alias in ("distort", "distortion", "warp", "distortion/warp"):
                self.assertIn(alias, warp_text)

            second = subprocess.run(["python3", str(SCRIPT), str(effects)], check=True, capture_output=True, text=True)
            self.assertIn("Normalized 0 of 2", second.stdout)


    def test_require_native_groups_rejects_irrecoverable_category_source(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            effects = Path(temporary) / "BuiltinEffects"
            effects.mkdir()
            (effects / "warp-only.xml").write_text(
                '<effect id="warp.only" name="Warp Only" category="warp"><spinner id="amount"/></effect>',
                encoding="utf-8",
            )
            completed = subprocess.run(
                ["python3", str(SCRIPT), "--require-native-groups", str(effects)],
                capture_output=True,
                text=True,
            )
            self.assertNotEqual(completed.returncode, 0)
            self.assertIn("Move/Transform", completed.stderr)


if __name__ == "__main__":
    unittest.main()
