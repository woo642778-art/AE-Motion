#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
from pathlib import Path
import tempfile
import unittest
import sys

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("visual_qualification", ROOT / "scripts/effect-visual-qualification.py")
visual = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
sys.modules[SPEC.name] = visual
SPEC.loader.exec_module(visual)


def rgba(width: int, height: int, color: tuple[int, int, int, int]) -> bytearray:
    return bytearray(color * (width * height))


def set_pixel(data: bytearray, width: int, x: int, y: int, color: tuple[int, int, int, int]) -> None:
    offset = (y * width + x) * 4
    data[offset:offset + 4] = bytes(color)


class VisualQualificationTests(unittest.TestCase):
    def test_detects_unexpected_top_black_bar(self) -> None:
        width, height = 40, 40
        source = rgba(width, height, (120, 80, 40, 255))
        output = bytearray(source)
        for y in range(2):
            for x in range(width):
                set_pixel(output, width, x, y, (0, 0, 0, 255))
        result = visual.analyze_rgba_output(bytes(source), bytes(output), width, height)
        self.assertEqual(result["disposition"], "failed")
        self.assertTrue(any(item["code"] == "unexpected_black_bar" for item in result["findings"]))

    def test_detects_blank_output(self) -> None:
        width, height = 16, 16
        source = rgba(width, height, (200, 120, 40, 255))
        output = rgba(width, height, (0, 0, 0, 255))
        result = visual.analyze_rgba_output(bytes(source), bytes(output), width, height)
        self.assertTrue(any(item["code"] == "blank_black_output" for item in result["findings"]))

    def test_detects_alpha_loss(self) -> None:
        width, height = 20, 20
        source = rgba(width, height, (100, 100, 100, 128))
        output = rgba(width, height, (100, 100, 100, 255))
        result = visual.analyze_rgba_output(bytes(source), bytes(output), width, height)
        self.assertTrue(any(item["code"] == "alpha_loss" for item in result["findings"]))

    def test_safe_output_passes(self) -> None:
        width, height = 20, 20
        source = rgba(width, height, (100, 80, 60, 128))
        output = rgba(width, height, (110, 90, 70, 128))
        result = visual.analyze_rgba_output(bytes(source), bytes(output), width, height)
        self.assertEqual(result["disposition"], "passed")

    def test_fixed_opaque_alpha_is_high_confidence_failure(self) -> None:
        text = '''<effect id="com.test.alpha"><params><texture id="inputImg" srcType="content"/></params><shader>void main(){ vec4 c=texture2DCv(inputImg.texture, acScreenNorm); gl_FragColor=vec4(c.rgb, 1.0); }</shader></effect>'''
        findings = visual.analyze_descriptor_text(text)
        self.assertTrue(any(item["code"] == "fixed_opaque_alpha" and item["confidence"] == "high" for item in findings))

    def test_unbounded_uv_offset_is_high_confidence_failure(self) -> None:
        text = '''<effect id="com.test.uv"><params><texture id="inputImg" srcType="content"/></params><shader>void main(){ gl_FragColor=texture2DCv(inputImg.texture, acScreenNorm + vec2(0.2)); }</shader></effect>'''
        findings = visual.analyze_descriptor_text(text)
        self.assertTrue(any(item["code"] == "unbounded_texture_coordinates" for item in findings))

    def test_zero_divisor_parameter_is_high_confidence_failure(self) -> None:
        text = '''<effect id="com.test.div"><params><texture id="inputImg" srcType="content"/><slider id="radius" min="0" max="10" default="1"/></params><shader>void main(){ vec2 uv=acScreenNorm/radius; gl_FragColor=texture2DCv(inputImg.texture, clamp(uv,0.0,1.0)); }</shader></effect>'''
        findings = visual.analyze_descriptor_text(text)
        self.assertTrue(any(item["code"] == "zero_permitted_divisor" for item in findings))

    def test_repaired_bcc_edge_glow_has_no_high_confidence_risk(self) -> None:
        result = visual.analyze_descriptor_visual_risk(ROOT / "Effects/v2.2/bccedgeglow.xml")
        self.assertNotEqual(result["disposition"], "failed")


if __name__ == "__main__":
    unittest.main()
