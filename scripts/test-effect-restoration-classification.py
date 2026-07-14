#!/usr/bin/env python3
from __future__ import annotations
import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "scripts/classify-effect-restoration.py"


def load_module():
    spec = importlib.util.spec_from_file_location("effect_restoration_classifier", MODULE_PATH)
    if spec is None or spec.loader is None:
        raise ImportError(MODULE_PATH)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def descriptor(shader: str = "gl_FragColor=vec4(1.0);", params: str = "", extra: str = "") -> str:
    return (
        f'<effect id="com.test.fx" name="FX" category="other"><params>{params}</params>'
        f'{extra}<shader type="fragment">void main(){{{shader}}}</shader></effect>'
    )


class RestorationClassificationTests(unittest.TestCase):
    def test_classifies_zero_permitted_division(self):
        classifier = load_module()
        xml = descriptor(
            shader="float x = value / amount; gl_FragColor=vec4(x);",
            params='<slider id="amount" min="0" max="1" default="0" step="0.1"/>',
        )
        findings = classifier.classify_descriptor(xml)
        self.assertIn("zero_permitted_divisor", {f.code for f in findings})

    def test_classifies_missing_pass_buffer(self):
        classifier = load_module()
        xml = descriptor(extra='<pass target="missing"/>')
        findings = classifier.classify_descriptor(xml)
        self.assertIn("missing_pass_buffer", {f.code for f in findings})

    def test_classifies_high_iteration_loop(self):
        classifier = load_module()
        xml = descriptor(
            shader="vec4 x=vec4(0.0); for(float i=0.0;i&lt;256.0;i+=1.0){x+=vec4(1.0);} gl_FragColor=x;"
        )
        findings = classifier.classify_descriptor(xml)
        self.assertIn("unsafe_loop", {f.code for f in findings})

    def test_semantic_exception_is_effect_id_specific(self):
        classifier = load_module()
        exceptions = classifier.load_semantic_exceptions(
            {"effects": {"com.test.bars": {"allowedFindings": ["intentional_bars_non_neutral"]}}}
        )
        self.assertTrue(exceptions.permits("com.test.bars", "intentional_bars_non_neutral"))
        self.assertFalse(exceptions.permits("com.test.other", "intentional_bars_non_neutral"))

    def test_declared_texture_source_is_not_missing_without_bundle_evidence(self):
        classifier = load_module()
        xml = (
            '<effect id="com.test.fx" name="FX" category="other"><params>'
            '<texture id="map" src="maps/fx.png"/></params><shader type="fragment">'
            'void main(){ gl_FragColor=vec4(1.0); }</shader></effect>'
        )
        findings = classifier.classify_descriptor(xml)
        self.assertNotIn("missing_resource", {f.code for f in findings})

    def test_declared_resource_is_not_missing_without_bundle_evidence(self):
        classifier = load_module()
        xml = (
            '<effect id="com.test.fx" name="FX" category="other" thumb="thumb/fx.png">'
            '<params/><shader type="fragment">void main(){ gl_FragColor=vec4(1.0); }</shader></effect>'
        )
        findings = classifier.classify_descriptor(xml)
        self.assertNotIn("missing_resource", {f.code for f in findings})

    def test_clean_descriptor_uses_static_revalidation_family(self):
        classifier = load_module()
        record = {"passes": [], "resources": []}
        self.assertEqual(classifier.repair_family([], record), "static_revalidation")

    def test_queue_uses_baseline_quarantine_and_explicit_beta19_ids(self):
        classifier = load_module()
        baseline = {
            "records": [
                {
                    "effectID": "com.test.initial",
                    "fileName": "a.xml",
                    "originalCategory": "blur",
                    "descriptorSHA256": "a" * 64,
                    "sourceLocation": "Payload/App.app/AEMotionQuarantine/BuiltinEffects/a.xml",
                },
                {
                    "effectID": "com.test.beta19",
                    "fileName": "b.xml",
                    "originalCategory": "other",
                    "descriptorSHA256": "b" * 64,
                    "sourceLocation": "Payload/App.app/BuiltinEffects/b.xml",
                },
                {
                    "effectID": "com.test.active",
                    "fileName": "c.xml",
                    "originalCategory": "color",
                    "descriptorSHA256": "c" * 64,
                    "sourceLocation": "Payload/App.app/BuiltinEffects/c.xml",
                },
            ]
        }
        texts = {
            "com.test.initial": descriptor(),
            "com.test.beta19": descriptor(),
            "com.test.active": descriptor(),
        }
        queue = classifier.build_queue(baseline, texts, {"com.test.beta19"})
        self.assertEqual([item.effectID for item in queue], ["com.test.beta19", "com.test.initial"])


if __name__ == "__main__":
    unittest.main()
