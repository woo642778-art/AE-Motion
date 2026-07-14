#!/usr/bin/env python3
from __future__ import annotations
import importlib.util
from pathlib import Path
import tempfile
import unittest
import sys

ROOT = Path(__file__).resolve().parents[1]
RESTORE_PATH = ROOT / "scripts/restore-other-effect-categories.py"
NORMALIZE_PATH = ROOT / "scripts/normalize-effect-search-metadata.py"

def load(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path); module = importlib.util.module_from_spec(spec); assert spec.loader; sys.modules[name] = module; spec.loader.exec_module(module); return module
restore = load(RESTORE_PATH, "restore_other")
normalize = load(NORMALIZE_PATH, "normalize_effects")

class OtherCategoryTests(unittest.TestCase):
    def test_normalizer_preserves_other_and_uses_other_fallback(self):
        self.assertEqual(normalize.normalize_category("other"), "other")
        self.assertEqual(normalize.normalize_category("Imported Custom"), "other")
        self.assertEqual(normalize.normalize_category("stylize"), "procedural")

    def test_restores_verified_existing_effect_without_changing_body_or_id(self):
        with tempfile.TemporaryDirectory() as temp:
            effects = Path(temp) / "BuiltinEffects"; effects.mkdir()
            path = effects / "fill.xml"
            body = '<effect id="com.alightcreative.effects.fillbehind" name="Fill" category="procedural" tags="fill"><shader>KEEP-ME</shader></effect>'
            path.write_text(body, encoding="utf-8")
            result = restore.restore_other_categories(effects)
            updated = path.read_text(encoding="utf-8")
            self.assertEqual(result.other_count, 1)
            self.assertIn('id="com.alightcreative.effects.fillbehind"', updated)
            self.assertIn('category="other"', updated)
            self.assertIn('<shader>KEEP-ME</shader>', updated)
            self.assertIn('tags="fill,other,imported"', updated)

    def test_does_not_restore_unverified_or_quarantined_absent_effects(self):
        with tempfile.TemporaryDirectory() as temp:
            effects = Path(temp) / "BuiltinEffects"; effects.mkdir()
            path = effects / "unknown.xml"
            path.write_text('<effect id="com.example.unknown" name="Unknown" category="procedural"><shader>x</shader></effect>', encoding="utf-8")
            result = restore.restore_other_categories(effects)
            self.assertEqual(result.matched, 0)
            self.assertNotIn('category="other"', path.read_text(encoding="utf-8"))

    def test_second_run_is_idempotent(self):
        with tempfile.TemporaryDirectory() as temp:
            effects = Path(temp) / "BuiltinEffects"; effects.mkdir()
            path = effects / "grid.xml"
            path.write_text('<effect id="com.alightcreative.effects.colorgrid" name="Grid" category="procedural"><shader>x</shader></effect>', encoding="utf-8")
            first = restore.restore_other_categories(effects); snapshot = path.read_bytes(); second = restore.restore_other_categories(effects)
            self.assertEqual(first.changed, 1); self.assertEqual(second.changed, 0); self.assertEqual(path.read_bytes(), snapshot)

if __name__ == "__main__": unittest.main()
