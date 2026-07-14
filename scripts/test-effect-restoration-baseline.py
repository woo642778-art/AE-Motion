#!/usr/bin/env python3
from __future__ import annotations
import importlib.util
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "scripts/build-effect-restoration-baseline.py"


def load_module():
    spec = importlib.util.spec_from_file_location("effect_restoration_baseline", MODULE_PATH)
    if spec is None or spec.loader is None:
        raise ImportError(f"Unable to load {MODULE_PATH}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def effect(effect_id: str, category: str, body: str = "") -> str:
    return (
        f'<?xml version="1.0"?><effect id="{effect_id}" name="Test" '
        f'category="{category}"><params><slider id="amount" min="0" max="1" '
        f'default="0.5" step="0.1"/></params><shader type="fragment">'
        f'void main(){{ gl_FragColor=vec4(1.0); }}{body}</shader></effect>'
    )


def make_ipa(path: Path, active: list[str], quarantined: list[str]) -> None:
    with zipfile.ZipFile(path, "w") as archive:
        for index, xml in enumerate(active):
            archive.writestr(f"Payload/Test.app/BuiltinEffects/active{index}.xml", xml)
        for index, xml in enumerate(quarantined):
            archive.writestr(f"Payload/Test.app/AEMotionQuarantine/BuiltinEffects/q{index}.xml", xml)


class BaselineBuilderTests(unittest.TestCase):
    def test_combines_active_and_quarantined_descriptors_by_effect_id(self):
        baseline = load_module()
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            ipa = root / "base.ipa"
            make_ipa(
                ipa,
                active=[effect("com.test.a", "blur")],
                quarantined=[effect("com.test.b", "Other")],
            )
            result = baseline.build_baseline(ipa)
            self.assertEqual(set(result.records), {"com.test.a", "com.test.b"})
            self.assertEqual(result.records["com.test.b"].originalCategory, "other")

    def test_duplicate_effect_id_with_different_descriptor_aborts(self):
        baseline = load_module()
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            ipa = root / "base.ipa"
            make_ipa(
                ipa,
                active=[effect("com.test.same", "blur")],
                quarantined=[effect("com.test.same", "other", body="//changed")],
            )
            with self.assertRaisesRegex(ValueError, "conflicting baseline descriptor"):
                baseline.build_baseline(ipa)

    def test_active_descriptor_wins_when_quarantine_copy_is_byte_identical(self):
        baseline = load_module()
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            ipa = root / "base.ipa"
            xml = effect("com.test.same", "blur")
            make_ipa(ipa, active=[xml], quarantined=[xml])
            result = baseline.build_baseline(ipa)
            self.assertEqual(len(result.records), 1)
            self.assertIn("/BuiltinEffects/active0.xml", result.records["com.test.same"].sourceLocation)

    def test_manifest_json_has_stable_sorted_records(self):
        baseline = load_module()
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            ipa = root / "base.ipa"
            make_ipa(ipa, active=[effect("com.test.z", "blur"), effect("com.test.a", "other")], quarantined=[])
            result = baseline.build_baseline(ipa)
            payload = baseline.manifest_to_json(result)
            self.assertEqual([item["effectID"] for item in payload["records"]], ["com.test.a", "com.test.z"])
            self.assertEqual(payload["effectCount"], 2)


if __name__ == "__main__":
    unittest.main()
