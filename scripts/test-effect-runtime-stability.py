#!/usr/bin/env python3
from __future__ import annotations
import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "scripts/effect-runtime-stability.py"


def load_module():
    spec = importlib.util.spec_from_file_location("runtime_stability", MODULE_PATH)
    if spec is None or spec.loader is None:
        raise ImportError(MODULE_PATH)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


SAFE_XML = '''<?xml version="1.0"?><effect id="{effect_id}" name="{name}" category="procedural"><params><texture id="inputImg" srcType="content"/></params><shader type="fragment">void main() {{ gl_FragColor=texture2DCv(inputImg.texture,acScreenNorm); }}</shader></effect>'''
RISKY_XML = '''<?xml version="1.0"?><effect id="com.test.risky" name="Risky" category="drawing"><params><texture id="inputImg" srcType="content"/></params><shader type="fragment">void main(){ vec4 c=vec4(0.0); for(float i=0.0;i&lt;256.0;i+=1.0){ c+=texture2DCv(inputImg.texture,acScreenNorm); } gl_FragColor=c/256.0; }</shader></effect>'''


class RuntimeEffectStabilityTests(unittest.TestCase):
    def make_app(self, root: Path) -> Path:
        app = root / "App.app"
        (app / "BuiltinEffects").mkdir(parents=True)
        return app

    def test_report_mode_records_errors_without_moving_descriptor(self):
        runtime = load_module()
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            app = self.make_app(root)
            path = app / "BuiltinEffects/risky.xml"
            path.write_text(RISKY_XML, encoding="utf-8")
            before = path.read_bytes()
            result = runtime.audit_runtime_stability(app)
            self.assertEqual(result["mode"], "report")
            self.assertEqual(result["errorCount"], 1)
            self.assertEqual(path.read_bytes(), before)
            self.assertFalse((app / "AEMotionQuarantine").exists())

    def test_report_mode_keeps_safe_descriptor(self):
        runtime = load_module()
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            app = self.make_app(root)
            path = app / "BuiltinEffects/safe.xml"
            path.write_text(SAFE_XML.format(effect_id="com.test.safe", name="Safe"), encoding="utf-8")
            result = runtime.audit_runtime_stability(app)
            self.assertEqual(result["errorCount"], 0)
            self.assertTrue(path.is_file())

    def test_legacy_quarantine_requires_explicit_function(self):
        runtime = load_module()
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            app = self.make_app(root)
            repair_dir = root / "repairs"
            repair_dir.mkdir()
            bcc = SAFE_XML.format(effect_id="com.alightcreative.effects.bccedgeglow", name="BCC Edge Glow")
            bars = SAFE_XML.format(effect_id="com.alightcreative.effects.bbmaker", name="Black Bars")
            (repair_dir / "bccedgeglow.xml").write_text(bcc, encoding="utf-8")
            (repair_dir / "blackbars.xml").write_text(bars, encoding="utf-8")
            (app / "BuiltinEffects/bcc.xml").write_text(bcc, encoding="utf-8")
            (app / "BuiltinEffects/bars.xml").write_text(bars, encoding="utf-8")
            (app / "BuiltinEffects/risky.xml").write_text(RISKY_XML, encoding="utf-8")
            result = runtime.repair_and_quarantine(app, repair_dir, root / "legacy.json")
            self.assertEqual(result["quarantined"], 1)
            self.assertFalse((app / "BuiltinEffects/risky.xml").exists())


if __name__ == "__main__":
    unittest.main()
