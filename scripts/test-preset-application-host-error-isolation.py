#!/usr/bin/env python3
from __future__ import annotations

import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Sources/AEMotionExtensionsHost/PresetApplicationContext.swift"

text = SOURCE.read_text(encoding="utf-8")
needle = "enum PresetApplicationHostError"
start = text.find(needle)
if start < 0:
    raise SystemExit(f"missing {needle} in {SOURCE}")

line_start = text.rfind("\n", 0, start) + 1
previous_line_end = line_start - 1
previous_line_start = text.rfind("\n", 0, max(0, previous_line_end)) + 1
prefix = text[previous_line_start:line_start].strip()
if prefix.startswith("@"):
    start = previous_line_start

brace_start = text.find("{", start)
if brace_start < 0:
    raise SystemExit("enum opening brace not found")

depth = 0
end = None
for index in range(brace_start, len(text)):
    char = text[index]
    if char == "{":
        depth += 1
    elif char == "}":
        depth -= 1
        if depth == 0:
            end = index + 1
            break
if end is None:
    raise SystemExit("enum closing brace not found")

enum_source = text[start:end]
compile_source = "import Foundation\n" + enum_source + "\n"

with tempfile.TemporaryDirectory(prefix="aemotion-v201-error-isolation-") as tmp:
    source_path = pathlib.Path(tmp) / "PresetApplicationHostError.swift"
    source_path.write_text(compile_source, encoding="utf-8")
    result = subprocess.run(
        ["swiftc", "-swift-version", "6", "-typecheck", str(source_path)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )

if result.returncode != 0:
    sys.stdout.write(result.stdout)
    raise SystemExit(
        "PresetApplicationHostError does not satisfy LocalizedError under Swift 6."
    )

print("PASS: PresetApplicationHostError satisfies LocalizedError under Swift 6")
