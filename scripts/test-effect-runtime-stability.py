#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
from pathlib import Path
import tempfile
import unittest
import sys

ROOT = Path(__file__).resolve().parents[1]


def load(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


runtime = load("runtime_stability", ROOT / "scripts/effect-runtime-stability.py")

SAFE_XML = '''<?xml version="1.0"?><effect id="{effect_id}" name="{name}" category="procedural" experimental="false" deprecated="false"><params><texture id="inputImg" srcType="content"/><slider id="amount" min="0" max="1" default="0.5" step="0.1"/></params><shader type="fragment">void main() {{ gl_FragColor = texture2DCv(inputImg.texture, acScreenNorm); }}</shader></effect>'''
RISKY_XML = '''<?xml version="1.0"?><effect id="com.test.risky" name="Risky" category="drawing"><params><texture id="inputImg" srcType="content"/></params><shader type="fragment">void main(){ vec4 c=vec4(0.0); for(float i=0.0;i&lt;256.0;i+=1.0){ c+=texture2DCv(inputImg.texture,acScreenNorm); } gl_FragColor=c/256.0; }</shader></effect>'''
ALPHA_RISK_XML = '''<?xml version="1.0"?><effect id="com.test.alpha" name="Alpha Risk" category="drawing"><params><texture id="inputImg" srcType="content"/></params><shader type="fragment">void main(){ vec4 c=texture2DCv(inputImg.texture,acScreenNorm); gl_FragColor=vec4(c.rgb,1.0); }</shader></effect>'''
UV_RISK_XML = '''<?xml version="1.0"?><effect id="com.test.uv" name="UV Risk" category="drawing"><params><texture id="inputImg" srcType="content"/></params><shader type="fragment">void main(){ gl_FragColor=texture2DCv(inputImg.texture,acScreenNorm+vec2(0.25)); }</shader></effect>'''


class RuntimeEffectStabilityTests(unittest.TestCase):
    def make_app(self, root: Path) -> Path:
        app = root / "AlightMotion.app"
        (app / "BuiltinEffects").mkdir(parents=True)
        return app

    def make_repair(self, root: Path) -> tuple[Path, str]:
        repair_dir = root / "repairs"
        repair_dir.mkdir()
        repair = SAFE_XML.format(effect_id="com.alightcreative.effects.bccedgeglow", name="BCC Edge Glow")
        (repair_dir / "bccedgeglow.xml").write_text(repair, encoding="utf-8")
        return repair_dir, repair

    def test_known_crash_effect_is_replaced_and_large_loop_is_quarantined(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            app = self.make_app(root)
            (app / "BuiltinEffects/bccedgeglow.xml").write_text(SAFE_XML.format(effect_id="com.alightcreative.effects.bccedgeglow", name="Old") + "<!-- old -->", encoding="utf-8")
            (app / "BuiltinEffects/risky.xml").write_text(RISKY_XML, encoding="utf-8")
            repair_dir, repair = self.make_repair(root)
            result = runtime.repair_and_quarantine(app, repair_dir, root / "manifest.json")
            self.assertEqual(result["repaired"], 1)
            self.assertEqual(result["quarantined"], 1)
            self.assertEqual((app / "BuiltinEffects/bccedgeglow.xml").read_text(), repair)
            self.assertFalse((app / "BuiltinEffects/risky.xml").exists())
            self.assertTrue((app / "AEMotionQuarantine/RuntimeEffects/risky.xml").exists())

    def test_repair_is_idempotent(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            app = self.make_app(root)
            repair_dir, repair = self.make_repair(root)
            (app / "BuiltinEffects/bccedgeglow.xml").write_text(repair, encoding="utf-8")
            first = runtime.repair_and_quarantine(app, repair_dir, root / "first.json")
            second = runtime.repair_and_quarantine(app, repair_dir, root / "second.json")
            self.assertEqual(first["quarantined"], 0)
            self.assertEqual(second["quarantined"], 0)
            self.assertEqual((app / "BuiltinEffects/bccedgeglow.xml").read_text(), repair)

    def test_fixed_opaque_alpha_is_quarantined(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            app = self.make_app(root)
            repair_dir, repair = self.make_repair(root)
            (app / "BuiltinEffects/bccedgeglow.xml").write_text(repair, encoding="utf-8")
            (app / "BuiltinEffects/alpha.xml").write_text(ALPHA_RISK_XML, encoding="utf-8")
            result = runtime.repair_and_quarantine(app, repair_dir, root / "manifest.json")
            self.assertEqual(result["quarantined"], 1)
            record = next(item for item in result["records"] if item["effectID"] == "com.test.alpha")
            self.assertTrue(any(item["code"] == "fixed_opaque_alpha" for item in record["findings"]))

    def test_unbounded_texture_coordinates_are_quarantined(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            app = self.make_app(root)
            repair_dir, repair = self.make_repair(root)
            (app / "BuiltinEffects/bccedgeglow.xml").write_text(repair, encoding="utf-8")
            (app / "BuiltinEffects/uv.xml").write_text(UV_RISK_XML, encoding="utf-8")
            result = runtime.repair_and_quarantine(app, repair_dir, root / "manifest.json")
            self.assertEqual(result["quarantined"], 1)
            self.assertTrue((app / "AEMotionQuarantine/RuntimeEffects/uv.xml").is_file())


if __name__ == "__main__":
    unittest.main()
