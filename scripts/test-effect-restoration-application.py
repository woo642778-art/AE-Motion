#!/usr/bin/env python3
from __future__ import annotations
import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "scripts/apply-effect-restoration.py"


def load_module():
    spec = importlib.util.spec_from_file_location("effect_restoration_application", MODULE_PATH)
    if spec is None or spec.loader is None:
        raise ImportError(MODULE_PATH)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def record(effect_id: str, category: str, file_name: str = "fx.xml") -> dict[str, object]:
    return {
        "effectID": effect_id,
        "fileName": file_name,
        "originalCategory": category,
        "descriptorSHA256": "a" * 64,
        "sourceLocation": f"Payload/App.app/AEMotionQuarantine/BuiltinEffects/{file_name}",
    }


def queue_record(effect_id: str, category: str, file_name: str = "fx.xml") -> dict[str, object]:
    return {
        "effectID": effect_id,
        "fileName": file_name,
        "originalCategory": category,
        "baselineDescriptorSHA256": "a" * 64,
        "repairFamily": "static_revalidation",
        "status": "unrepaired",
    }


def apply_fixture(repaired: str, category: str = "other", effect_id: str = "com.test.fx"):
    module = load_module()
    with tempfile.TemporaryDirectory() as raw:
        root = Path(raw)
        app = root / "App.app"
        effects = app / "BuiltinEffects"
        effects.mkdir(parents=True)
        repair_root = root / "repairs"
        repair_root.mkdir()
        (repair_root / "fx.xml").write_text(repaired, encoding="utf-8")
        baseline = {"records": [record(effect_id, category)]}
        queue = {"records": [queue_record(effect_id, category)]}
        return module.apply_repairs(app, baseline, queue, repair_root)


class RestorationApplicationTests(unittest.TestCase):
    def test_preserves_effect_id_and_original_category(self):
        result = apply_fixture('<effect id="com.test.fx" category="other"><params/></effect>')
        self.assertEqual(result.appliedIDs, ["com.test.fx"])
        self.assertEqual(result.records[0].originalCategory, "other")

    def test_rejects_repair_with_changed_id(self):
        with self.assertRaisesRegex(ValueError, "effect ID changed"):
            apply_fixture('<effect id="com.test.changed" category="blur"/>', category="blur")

    def test_rejects_repair_with_changed_category(self):
        with self.assertRaisesRegex(ValueError, "category mismatch"):
            apply_fixture('<effect id="com.test.fx" category="other"/>', category="blur")

    def test_rejects_missing_repair_descriptor(self):
        module = load_module()
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            app = root / "App.app"
            (app / "BuiltinEffects").mkdir(parents=True)
            with self.assertRaisesRegex(FileNotFoundError, "repair descriptor missing"):
                module.apply_repairs(
                    app,
                    {"records": [record("com.test.fx", "blur")]},
                    {"records": [queue_record("com.test.fx", "blur")]},
                    root / "repairs",
                )

    def test_does_not_mutate_canonical_queue(self):
        module = load_module()
        queue = {"records": [queue_record("com.test.fx", "other")]}
        snapshot = json.dumps(queue, sort_keys=True)
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            app = root / "App.app"
            (app / "BuiltinEffects").mkdir(parents=True)
            repair_root = root / "repairs"
            repair_root.mkdir()
            (repair_root / "fx.xml").write_text('<effect id="com.test.fx" category="other"/>')
            module.apply_repairs(app, {"records": [record("com.test.fx", "other")]}, queue, repair_root)
        self.assertEqual(json.dumps(queue, sort_keys=True), snapshot)


if __name__ == "__main__":
    unittest.main()
