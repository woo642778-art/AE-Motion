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


if __name__ == "__main__":
    unittest.main()
