#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
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
other = load("other_restore", ROOT / "scripts/restore-other-effect-categories.py")

SAFE_XML = '''<?xml version="1.0"?><effect id="{effect_id}" name="{name}" category="procedural" experimental="false" deprecated="false"><params><texture id="inputImg" srcType="content"/><slider id="amount" min="0" max="1" default="0.5" step="0.1"/></params><shader type="fragment">void main() {{ gl_FragColor = texture2DCv(inputImg.texture, acScreenNorm); }}</shader></effect>'''
RISKY_XML = '''<?xml version="1.0"?><effect id="com.test.risky" name="Risky" category="drawing"><params><texture id="inputImg" srcType="content"/></params><shader type="fragment">void main(){ vec4 c=vec4(0.0); for(float i=0.0;i&lt;256.0;i+=1.0){ c+=texture2DCv(inputImg.texture,acScreenNorm); } gl_FragColor=c/256.0; }</shader></effect>'''

class RuntimeEffectStabilityTests(unittest.TestCase):
    def make_app(self, root: Path) -> Path:
        app = root / "AlightMotion.app"
        (app / "BuiltinEffects").mkdir(parents=True)
        return app

    def test_known_crash_effect_is_replaced_and_large_loop_is_quarantined(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            app = self.make_app(root)
            (app / "BuiltinEffects/bccedgeglow.xml").write_text(SAFE_XML.format(effect_id="com.alightcreative.effects.bccedgeglow", name="Old") + "<!-- old -->", encoding="utf-8")
            (app / "BuiltinEffects/risky.xml").write_text(RISKY_XML, encoding="utf-8")
            repair_dir = root / "repairs"; repair_dir.mkdir()
            repair = SAFE_XML.format(effect_id="com.alightcreative.effects.bccedgeglow", name="BCC Edge Glow")
            (repair_dir / "bccedgeglow.xml").write_text(repair, encoding="utf-8")
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
            repair_dir = root / "repairs"; repair_dir.mkdir()
            repair = SAFE_XML.format(effect_id="com.alightcreative.effects.bccedgeglow", name="BCC Edge Glow")
            (repair_dir / "bccedgeglow.xml").write_text(repair, encoding="utf-8")
            (app / "BuiltinEffects/bccedgeglow.xml").write_text(repair, encoding="utf-8")
            first = runtime.repair_and_quarantine(app, repair_dir, root / "first.json")
            second = runtime.repair_and_quarantine(app, repair_dir, root / "second.json")
            self.assertEqual(first["quarantined"], 0)
            self.assertEqual(second["quarantined"], 0)
            self.assertEqual((app / "BuiltinEffects/bccedgeglow.xml").read_text(), repair)

    def test_other_restoration_selects_only_runtime_safe_descriptors(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            app = self.make_app(root)
            records = []
            for index in range(8):
                effect_id = f"com.test.safe{index}"
                (app / f"BuiltinEffects/safe{index}.xml").write_text(SAFE_XML.format(effect_id=effect_id, name=f"Safe {index}"), encoding="utf-8")
                records.append({"effectID": effect_id, "status": "existingWorking", "dependencies": [], "resources": [], "findings": []})
            (app / "BuiltinEffects/risky.xml").write_text(RISKY_XML, encoding="utf-8")
            records.append({"effectID": "com.test.risky", "status": "existingWorking", "dependencies": [], "resources": [], "findings": []})
            report = root / "report.json"; report.write_text(json.dumps({"records": records}), encoding="utf-8")
            result = other.restore_other_categories(app, report, target_count=6, manifest_path=root / "other.json")
            self.assertGreaterEqual(result.otherCount, 6)
            self.assertNotIn("com.test.risky", result.selectedEffectIDs)
            first = {p.name: p.read_text() for p in (app / "BuiltinEffects").glob("*.xml")}
            second = other.restore_other_categories(app, report, target_count=6)
            self.assertEqual(first, {p.name: p.read_text() for p in (app / "BuiltinEffects").glob("*.xml")})
            self.assertEqual(result.otherCount, second.otherCount)

if __name__ == "__main__": unittest.main()
