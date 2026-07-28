#!/usr/bin/env python3
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
coordinator = (ROOT / "Sources/AEMotionUI271Host/AEMotionGlobalShellCoordinator.swift").read_text(encoding="utf-8")
shell = (ROOT / "Sources/AEMotionUI271Host/AEMotionShellViewController.swift").read_text(encoding="utf-8")
container_path = ROOT / "Sources/AEMotionUI271Host/AEMotionRootContainerViewController.swift"
container = container_path.read_text(encoding="utf-8") if container_path.exists() else ""

checks = {
    "root container exists": (container, r"final class AEMotionRootContainerViewController"),
    "original root embedded": (container, r"hostController.*addChild\(hostController\)"),
    "shell embedded above host": (container, r"addChild\(shellController\).*bringSubviewToFront"),
    "main window root replaced once": (coordinator, r"window\.rootViewController\s*=\s*container"),
    "window selected by full-screen area": (coordinator, r"bounds\.width\s*\*\s*.*bounds\.height"),
    "shell no longer constrained to host view": (shell, r"func configure\(tab:.*showsHomeContent:"),
    "project center touch passthrough": (shell, r"interactiveRegions.*hitTest.*return nil"),
}

failed = [name for name, (text, pattern) in checks.items() if re.search(pattern, text, re.S) is None]
if "attach(to host:" in shell or "host.view.addSubview(view)" in shell:
    failed.append("obsolete partial-host attachment remains")
if failed:
    print("FAIL: " + ", ".join(failed))
    sys.exit(1)
print("PASS: full-window root and touch-routing contract")
