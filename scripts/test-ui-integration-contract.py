#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def exists(path: str) -> bool:
    return (ROOT / path).exists()


def require(text: str, token: str, name: str, checks: dict[str, bool]) -> None:
    checks[name] = token in text


checks = {
    "theme file": exists("Sources/AEMotionExtensionsHost/AEMotionTheme.swift"),
    "tool factory": exists("Sources/AEMotionExtensionsHost/ToolControllerFactory.swift"),
    "safe tool registry": exists("Sources/AEMotionExtensionsCore/SafeToolRegistry.swift"),
    "unavailable tool screen": exists("Sources/AEMotionExtensionsHost/UnavailableToolViewController.swift"),
    "tool presentation guard": exists("Sources/AEMotionExtensionsHost/ToolPresentationGuard.swift"),
    "effect integrity screen": exists("Sources/AEMotionExtensionsHost/EffectIntegrityViewController.swift"),
    "host editing bridge": exists("Sources/AEMotionExtensionsHost/HostEditingContextBridge.swift"),
    "live preview coordinator": exists("Sources/AEMotionExtensionsHost/LivePreviewCoordinator.swift"),
    "contextual injector": exists("Sources/AEMotionExtensionsHost/ContextualButtonInjector.swift"),
    "contextual editor": exists("Sources/AEMotionExtensionsHost/ContextualEditingViewController.swift"),
    "standalone animation studio removed": not exists("Sources/AEMotionExtensionsHost/AnimationStudioViewController.swift"),
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
bootstrap = read("Sources/AEMotionExtensionsHost/Bootstrap.swift")
extensions = read("Sources/AEMotionExtensionsHost/ExtensionsViewController.swift")
tool_registry = read("Sources/AEMotionExtensionsCore/ToolRegistry.swift")
safe_registry = read("Sources/AEMotionExtensionsCore/SafeToolRegistry.swift")
tool_factory = read("Sources/AEMotionExtensionsHost/ToolControllerFactory.swift")
presentation_guard = read("Sources/AEMotionExtensionsHost/ToolPresentationGuard.swift")
bridge = read("Sources/AEMotionExtensionsHost/HostEditingContextBridge.swift")
coordinator = read("Sources/AEMotionExtensionsHost/LivePreviewCoordinator.swift")
injector = read("Sources/AEMotionExtensionsHost/ContextualButtonInjector.swift")
context_ui = read("Sources/AEMotionExtensionsHost/ContextualEditingViewController.swift")

checks.update({
    "project editor hook candidates": "projectEditorControllerNames" in runtime,
    "contextual installer from project editor": "ContextualButtonInjector.install(in: self)" in runtime,
    "contextual runtime hook bootstrap": "ContextualButtonInjector.installRuntimeHook()" in bootstrap,
    "legacy global editing toolbar removed": "aemotion_installProjectToolsIfNeeded" not in runtime and "Project Editing" not in runtime,
    "effect picker background normalization": "aemotion_normalizeEffectPickerAppearance" in runtime,
    "immutable registry snapshot": "registrySnapshot = SafeToolRegistry.snapshot()" in extensions,
    "recent section": "Recent" in extensions,
    "themed empty state": "AEMotionTheme.emptyState" in extensions,
    "editing shortcuts section removed": 'title: "Editing Shortcuts"' not in extensions,
    "independent IDs centralized": "independentToolIDs" in safe_registry,
    "typed tool construction": "ToolBuildResult" in tool_factory and "buildResult" in tool_factory,
    "row presentation isolation": "ToolPresentationGuard.push" in extensions,
    "unavailable destination": "UnavailableToolViewController" in presentation_guard,
    "rapid tap guard": "isOpeningTool" in extensions,
    "animation core absent from registry": '"animation.core"' not in tool_registry,
    "animation core absent from factory": 'case "animation.core"' not in tool_factory,
    "fail closed bridge": "guard contract.isSupported" in bridge,
    "ui control value change": "sendActions(for: .valueChanged)" in bridge,
    "preview invalidation": "setNeedsDisplay" in coordinator or "setNeedsDisplay" in bridge,
    "selection rollback": "selectionDidChange" in coordinator,
    "no private database access": "NSPersistentStore" not in bridge and "sqlite" not in bridge.lower(),
    "transform contextual button": "aemotion.context.transform" in injector,
    "graph contextual button": "aemotion.context.graph" in injector,
    "speed contextual button": "aemotion.context.speed" in injector,
    "effect contextual button": "aemotion.context.effect" in injector,
    "live preview update path": "coordinator.update" in context_ui,
    "cancel rollback path": "coordinator.cancel" in context_ui,
    "no render reimport": "AVAssetExportSession" not in context_ui and "PHPhotoLibrary" not in context_ui,
    "independent utilities button": "aemotion.install.utilities" in injector,
    "legacy project button removed by injector": "aemotion.install.project.tools" in injector,
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
