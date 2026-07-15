#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def test_timeline_ui_is_long_press_contextual_and_multi_select() -> None:
    source = read("Sources/AEMotionExtensionsHost/TimelineMultiSelectionController.swift")
    assert "UILongPressGestureRecognizer" in source
    assert "selectedLayerIDs" in source
    assert 'title: "Pre-compose"' in source
    assert "selectedLayerIDs.count >= 2" in source
    assert "aemotion.timeline.multi-select-bar" in source
    assert "setSelectedLayerIDs" in source


def test_precompose_sheet_uses_live_transaction_and_auto_trim_engine() -> None:
    source = read("Sources/AEMotionExtensionsHost/PrecomposeViewController.swift")
    assert "CompositionLivePreviewCoordinator" in source
    assert "PrecomposeEngine.precompose" in source
    assert "coordinator.update" in source
    assert "coordinator.commit" in source
    assert "coordinator.cancel" in source
    assert 'title = "Pre-compose"' in source
    assert "structuralPrecompose" in source


def test_composition_inspector_exposes_all_approved_sections_and_live_updates() -> None:
    source = read("Sources/AEMotionExtensionsHost/CompositionInspectorViewController.swift")
    for token in ["Blend", "Track Matte", "Parent", "Alpha", "Channels"]:
        assert token in source
    assert "BlendModeCatalogue" in source
    assert "supportedBlendModeIDs" in source
    assert "Alpha Inverted" in source
    assert "Luma Inverted" in source
    assert "UIPanGestureRecognizer" in source
    assert "CompositionMutationEngine" in source
    assert "coordinator.update" in source
    assert "coordinator.commit" in source
    assert "coordinator.cancel" in source


def test_host_declares_exact_supported_blend_ids() -> None:
    contract = read("Sources/AEMotionExtensionsHost/CompositionHostContract.swift")
    bridge = read("Sources/AEMotionExtensionsHost/CompositionHostBridge.swift")
    assert "supportedBlendModeIDs" in contract
    assert "aemotionSupportedBlendModeIdentifiers" in bridge


def test_null_group_is_live_atomic_and_world_preserving() -> None:
    source = read("Sources/AEMotionExtensionsHost/NullGroupViewController.swift")
    engine = read("Sources/AEMotionExtensionsCore/NullGroupEngine.swift")
    assert "NullGroupEngine.group" in source
    assert "CompositionMutationEngine.addNull" in engine
    assert "insertionIndex" in engine
    assert "CompositionMutationEngine.setParent" in engine
    assert "CompositionLivePreviewCoordinator" in source
    assert "coordinator.update" in source
    assert "coordinator.commit" in source
    assert "coordinator.cancel" in source


def test_composition_editing_controller_routes_contextual_actions() -> None:
    source = read("Sources/AEMotionExtensionsHost/CompositionEditingController.swift")
    assert "TimelineMultiSelectionControllerDelegate" in source
    assert "PrecomposeViewController" in source
    assert "CompositionInspectorViewController" in source
    assert "NullGroupViewController" in source
    assert "presentInspectorForCurrentSelection" in source


def test_contextual_injector_installs_composition_editor_outside_extensions_hub() -> None:
    injector = read("Sources/AEMotionExtensionsHost/ContextualButtonInjector.swift")
    factory = read("Sources/AEMotionExtensionsHost/ToolControllerFactory.swift")
    assert "installCompositionEditingIfNeeded" in injector
    assert "aemotion.composition.inspector" in injector
    assert "CompositionEditingController" in injector
    assert "CompositionEditingController" not in factory
