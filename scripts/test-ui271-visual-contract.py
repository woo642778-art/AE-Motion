#!/usr/bin/env python3
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
files = {
    "theme": ROOT / "Sources/AEMotionUI271Host/AEMotionProductTheme.swift",
    "motion": ROOT / "Sources/AEMotionUI271Host/AEMotionMotionSystem.swift",
    "ambient": ROOT / "Sources/AEMotionUI271Host/AEMotionAmbientFieldView.swift",
    "card": ROOT / "Sources/AEMotionUI271Host/AEMotionSpotlightCard.swift",
}
text = {name: path.read_text(encoding="utf-8") for name, path in files.items()}

checks = {
    "near black canvas": (text["theme"], r'canvas.*UIColor'),
    "purple accent": (text["theme"], r'accentPurple'),
    "minimum touch target": (text["theme"], r'minimumTouchTarget\s*:\s*CGFloat\s*=\s*44'),
    "reduce motion": (text["motion"], r'UIAccessibility\.isReduceMotionEnabled'),
    "interruptible animator": (text["motion"], r'UIViewPropertyAnimator'),
    "reduce transparency": (text["ambient"], r'UIAccessibility\.isReduceTransparencyEnabled'),
    "ambient pause": (text["ambient"], r'func\s+pauseAnimation'),
    "ambient resume": (text["ambient"], r'func\s+resumeAnimation'),
    "touch spotlight": (text["card"], r'updateSpotlight\(at:'),
    "radial gradient": (text["card"], r'\.radial'),
    "content layout": (text["card"], r'numberOfLines\s*=\s*0'),
}

combined = "\n".join(text.values())
if re.search(r'WKWebView|JavaScriptCore|React|Tailwind', combined):
    print("FAIL: forbidden web implementation")
    sys.exit(1)

failed = [name for name, (content, pattern) in checks.items() if re.search(pattern, content, re.S) is None]
if failed:
    print("FAIL: " + ", ".join(failed))
    sys.exit(1)
print("PASS: UI 2.7.1 visual contract")
