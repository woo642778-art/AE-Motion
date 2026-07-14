#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import plistlib
import shutil
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent
FIXTURES = ROOT / "fixtures" / "effects"

from effect_descriptor import parse_effect


def load_script(name: str, module_name: str):
    spec = importlib.util.spec_from_file_location(module_name, ROOT / name)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


audit_module = load_script("audit-builtin-effects.py", "audit_builtin_effects")
quarantine_module = load_script("quarantine-builtin-effects.py", "quarantine_builtin_effects")


class EffectDescriptorTests(unittest.TestCase):
    def test_parses_valid_effect(self):
        effect = parse_effect(FIXTURES / "valid-single-pass.xml")
        self.assertEqual(effect.effect_id, "com.aemotion.fixture.valid")
        self.assertEqual(effect.name, "Valid Fixture")
        self.assertEqual(effect.category, "procedural")
        self.assertEqual(effect.parameter_signature(), "amount:slider,inputImg:texture")
        self.assertIsNotNone(effect.shader_sha256)

    def test_extracts_missing_pass_dependency(self):
        effect = parse_effect(FIXTURES / "missing-pass.xml")
        self.assertEqual(effect.dependencies, ("com.aemotion.fixture.helper",))

    def test_extracts_external_texture(self):
        effect = parse_effect(FIXTURES / "missing-texture.xml")
        self.assertEqual(effect.resources, ("textures/missing.png",))
        self.assertIn("missing_resource", {finding.code for finding in effect.findings})

    def test_rejects_invalid_slider_range(self):
        effect = parse_effect(FIXTURES / "invalid-range.xml")
        self.assertIn("invalid_parameter_range", {finding.code for finding in effect.findings})


class AuditTests(unittest.TestCase):
    def test_duplicate_ids_are_blockers(self):
        report = audit_module.audit_directory(FIXTURES / "duplicates-root")
        statuses = {record["fileName"]: record["status"] for record in report["records"]}
        self.assertEqual(statuses["duplicate-a.xml"], "duplicate")
        self.assertEqual(statuses["duplicate-b.xml"], "duplicate")

    def test_missing_dependency_is_unsupported(self):
        with tempfile.TemporaryDirectory() as tmp:
            effects = Path(tmp) / "BuiltinEffects"
            effects.mkdir()
            shutil.copy2(FIXTURES / "missing-pass.xml", effects / "missing-pass.xml")
            report = audit_module.audit_directory(Path(tmp))
            self.assertEqual(report["records"][0]["status"], "unsupportedDependency")


class QuarantineTests(unittest.TestCase):
    def _app(self, root: Path) -> tuple[Path, Path]:
        app = root / "AlightMotion.app"
        effects = app / "BuiltinEffects"
        effects.mkdir(parents=True)
        shutil.copy2(FIXTURES / "valid-single-pass.xml", effects / "valid.xml")
        shutil.copy2(FIXTURES / "missing-texture.xml", effects / "broken.xml")
        with (app / "Info.plist").open("wb") as handle:
            plistlib.dump({"CFBundleShortVersionString": "1", "CFBundleVersion": "1"}, handle)
        return app, effects

    def test_quarantine_moves_only_unsafe_effects(self):
        with tempfile.TemporaryDirectory() as tmp:
            app, effects = self._app(Path(tmp))
            report = audit_module.audit_directory(app)
            report_path = Path(tmp) / "effect-integrity.json"
            report_path.write_text(json.dumps(report), encoding="utf-8")
            manifest_path = Path(tmp) / "quarantine-manifest.json"
            quarantine_module.quarantine(app, report_path, manifest_path, "apply")
            self.assertTrue((effects / "valid.xml").exists())
            self.assertFalse((effects / "broken.xml").exists())
            self.assertTrue((app / "AEMotionQuarantine/BuiltinEffects/broken.xml").exists())
            self.assertTrue((app / "AEMotionDiagnostics/effect-integrity.json").exists())
            self.assertTrue((app / "AEMotionDiagnostics/quarantine-manifest.json").exists())

    def test_dry_run_does_not_modify_app(self):
        with tempfile.TemporaryDirectory() as tmp:
            app, effects = self._app(Path(tmp))
            report = audit_module.audit_directory(app)
            report_path = Path(tmp) / "effect-integrity.json"
            report_path.write_text(json.dumps(report), encoding="utf-8")
            quarantine_module.quarantine(app, report_path, None, "dry-run")
            self.assertTrue((effects / "broken.xml").exists())
            self.assertFalse((app / "AEMotionQuarantine").exists())


if __name__ == "__main__":
    unittest.main()
