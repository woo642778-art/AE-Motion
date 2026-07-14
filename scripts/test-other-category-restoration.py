#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import sys

ROOT = Path(__file__).resolve().parents[1]


def load(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


restore = load(ROOT / "scripts/restore-other-effect-categories.py", "restore_other")
selector = load(ROOT / "scripts/select-qualified-other-effects.py", "select_other")
normalize = load(ROOT / "scripts/normalize-effect-search-metadata.py", "normalize_effects")


def descriptor(effect_id: str, category: str = "procedural") -> str:
    return f'<effect id="{effect_id}" name="Test" category="{category}" tags="test"><shader>void main(){{gl_FragColor=vec4(1.0);}}</shader></effect>'


def write_reports(root: Path, effect_id: str, descriptor_hash: str, device_hash: str | None, disposition: str = "passed") -> tuple[Path, Path, Path]:
    integrity = root / "integrity.json"
    ci = root / "ci.json"
    device = root / "device.json"
    integrity.write_text(json.dumps({"records": [{"effectID": effect_id, "descriptorSHA256": descriptor_hash, "status": "existingWorking", "dependencies": [], "resources": [], "findings": []}]}), encoding="utf-8")
    ci.write_text(json.dumps({"records": [{"effectID": effect_id, "descriptorSHA256": descriptor_hash, "stage": "ci", "disposition": "passed", "findings": []}]}), encoding="utf-8")
    records = [] if device_hash is None else [{"effectID": effect_id, "descriptorSHA256": device_hash, "stage": "device", "disposition": disposition, "hostVersion": "6.2.42", "deviceClass": "iPhone", "metrics": {}}]
    device.write_text(json.dumps({"schemaVersion": 1, "records": records}), encoding="utf-8")
    return integrity, ci, device


class OtherCategoryTests(unittest.TestCase):
    def test_normalizer_preserves_other_but_selection_is_evidence_based(self) -> None:
        self.assertEqual(normalize.normalize_category("other"), "other")
        self.assertEqual(normalize.normalize_category("Imported Custom"), "other")
        self.assertEqual(normalize.normalize_category("stylize"), "procedural")

    def test_only_exact_hash_device_pass_enters_other(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            app = root / "App.app"
            effects = app / "BuiltinEffects"
            effects.mkdir(parents=True)
            effect_id = "com.test.pass"
            path = effects / "pass.xml"
            path.write_text(descriptor(effect_id), encoding="utf-8")
            descriptor_hash = hashlib.sha256(path.read_bytes()).hexdigest()
            integrity, ci, device = write_reports(root, effect_id, descriptor_hash, descriptor_hash)
            result = restore.restore_other_categories(app, integrity, ci, device, root / "selection.json")
            self.assertEqual(result.otherCount, 1)
            self.assertEqual(result.selectedEffectIDs, [effect_id])
            self.assertIn('category="other"', path.read_text(encoding="utf-8"))

    def test_stale_hash_does_not_enter_other(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            app = root / "App.app"
            effects = app / "BuiltinEffects"
            effects.mkdir(parents=True)
            effect_id = "com.test.stale"
            path = effects / "stale.xml"
            path.write_text(descriptor(effect_id), encoding="utf-8")
            descriptor_hash = hashlib.sha256(path.read_bytes()).hexdigest()
            integrity, ci, device = write_reports(root, effect_id, descriptor_hash, "d" * 64)
            result = restore.restore_other_categories(app, integrity, ci, device)
            self.assertEqual(result.otherCount, 0)
            self.assertNotIn('category="other"', path.read_text(encoding="utf-8"))

    def test_empty_evidence_produces_zero_other_without_error(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            app = root / "App.app"
            effects = app / "BuiltinEffects"
            effects.mkdir(parents=True)
            effect_id = "com.test.empty"
            path = effects / "empty.xml"
            path.write_text(descriptor(effect_id, category="other"), encoding="utf-8")
            descriptor_hash = hashlib.sha256(path.read_bytes()).hexdigest()
            integrity, ci, device = write_reports(root, effect_id, descriptor_hash, None)
            result = restore.restore_other_categories(app, integrity, ci, device)
            self.assertEqual(result.otherCount, 0)
            self.assertIn('category="procedural"', path.read_text(encoding="utf-8"))

    def test_selector_matches_only_exact_pass(self) -> None:
        descriptors = {"com.test.pass": "a" * 64, "com.test.stale": "b" * 64, "com.test.fail": "c" * 64}
        records = [
            {"effectID": "com.test.pass", "descriptorSHA256": "a" * 64, "stage": "device", "disposition": "passed"},
            {"effectID": "com.test.stale", "descriptorSHA256": "d" * 64, "stage": "device", "disposition": "passed"},
            {"effectID": "com.test.fail", "descriptorSHA256": "c" * 64, "stage": "device", "disposition": "failed"},
        ]
        self.assertEqual(selector.eligible_ids(descriptors, records), {"com.test.pass"})

    def test_second_run_is_idempotent(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            app = root / "App.app"
            effects = app / "BuiltinEffects"
            effects.mkdir(parents=True)
            effect_id = "com.test.idempotent"
            path = effects / "idempotent.xml"
            path.write_text(descriptor(effect_id), encoding="utf-8")
            descriptor_hash = hashlib.sha256(path.read_bytes()).hexdigest()
            integrity, ci, device = write_reports(root, effect_id, descriptor_hash, descriptor_hash)
            first = restore.restore_other_categories(app, integrity, ci, device)
            snapshot = path.read_bytes()
            second = restore.restore_other_categories(app, integrity, ci, device)
            self.assertEqual(first.changed, 1)
            self.assertEqual(second.changed, 0)
            self.assertEqual(path.read_bytes(), snapshot)


if __name__ == "__main__":
    unittest.main()
