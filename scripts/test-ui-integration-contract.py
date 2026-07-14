#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def require(text: str, token: str, name: str, checks: dict[str, bool]) -> None:
    checks[name] = token in text


checks = {
    "theme file": (ROOT / "Sources/AEMotionExtensionsHost/AEMotionTheme.swift").exists(),
    "tool factory": (ROOT / "Sources/AEMotionExtensionsHost/ToolControllerFactory.swift").exists(),
    "effect integrity screen": (ROOT / "Sources/AEMotionExtensionsHost/EffectIntegrityViewController.swift").exists(),
}

if checks["theme file"]:
    theme = read("Sources/AEMotionExtensionsHost/AEMotionTheme.swift")
    checks.update({
        "semantic grouped background": "systemGroupedBackground" in theme,
        "empty state component": "emptyState" in theme,
        "table styling": "apply(to tableView" in theme,
        "scroll styling": "apply(to scrollView" in theme,
    })

runtime = read("Sources/AEMotionExtensionsHost/RuntimeResolver.swift")
checks.update({
    "project editor hook candidates": "projectEditorControllerNames" in runtime,
    "contextual project toolbar": "aemotion.install.project.tools" in runtime,
    "effect picker background normalization": "aemotion_normalizeEffectPickerAppearance" in runtime,
})

extensions = read("Sources/AEMotionExtensionsHost/ExtensionsViewController.swift")
tool_registry = read("Sources/AEMotionExtensionsCore/ToolRegistry.swift")
tool_factory = read("Sources/AEMotionExtensionsHost/ToolControllerFactory.swift")
checks.update({
    "dynamic visible sections": "visibleSections" in extensions,
    "recent section": "Recent" in extensions,
    "themed empty state": "AEMotionTheme.emptyState" in extensions,
})
require(tool_registry, '"effects.integrity"', "effect integrity tool", checks)
require(tool_factory, 'case "effects.integrity"', "effect integrity controller", checks)
require(extensions, '"effects.integrity"', "effect integrity diagnostics row", checks)

proxy = read("Sources/AEMotionExtensionsHost/CategoryCollectionProxy.swift")
checks.update({
    "themed extension category": "AEMotionTheme" in proxy,
    "category background surface": "backgroundView" in proxy,
})

failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(f"{'PASS' if ok else 'FAIL'}: {name}")
if failed:
    raise SystemExit(f"UI integration contract failed: {', '.join(failed)}")
