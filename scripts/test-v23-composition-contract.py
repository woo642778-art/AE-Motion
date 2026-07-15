#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def test_composition_bridge_is_fail_closed() -> None:
    contract = read("Sources/AEMotionExtensionsHost/CompositionHostContract.swift")
    bridge = read("Sources/AEMotionExtensionsHost/CompositionHostBridge.swift")
    assert "enum CompositionHostCapability" in contract
    assert "verifiedCapabilities" in contract
    assert "required.isSubset" in bridge
    assert "snapshot.hasStableSelection" in bridge
    assert "CompositionValidator.validate" in bridge
    assert "return nil" in bridge


def test_timeline_selection_requires_explicit_host_contract() -> None:
    contract = read("Sources/AEMotionExtensionsHost/CompositionHostContract.swift")
    bridge = read("Sources/AEMotionExtensionsHost/CompositionHostBridge.swift")
    assert "HostTimelineFrame" in contract
    assert "case mutateSelection" in contract
    assert "setSelectedLayerIDs" in contract
    assert "aemotionSetSelectedLayerIdentifiersJSON:" in bridge
    assert "verifiedCapabilities.contains(.mutateSelection)" in bridge


def test_structural_commit_requires_postcondition_verification() -> None:
    bridge = read("Sources/AEMotionExtensionsHost/CompositionHostBridge.swift")
    assert "verifyPostcondition" in bridge
    assert "nativeDocument == intent.finalDocument" in bridge
    assert "aemotionVerifyCompositionIntentJSON:" in bridge


def test_no_private_database_or_render_reimport_path() -> None:
    text = "\n".join(path.read_text(errors="ignore") for path in (ROOT / "Sources").rglob("*.swift")).lower()
    for forbidden in ["sqlite3_exec", "timeline.db", "project.db", "nspersistentstore", "avassetexportsession", "phphotolibrary"]:
        assert forbidden not in text


def test_live_preview_has_required_cancellation_and_commit_paths() -> None:
    source = read("Sources/AEMotionExtensionsHost/CompositionLivePreviewCoordinator.swift")
    assert "CADisplayLink" in source
    assert "selectionDidChange" in source
    assert "applicationDidEnterBackground" in source
    assert "verifyPostcondition" in source
    assert "commitPostconditionFailed" in source
    assert "restoreAfterFailedCommit" in source
    assert "temporaryOverlay?.removeFromSuperview" in source


if __name__ == "__main__":
    tests = sorted((name, value) for name, value in globals().items() if name.startswith("test_") and callable(value))
    for name, test in tests:
        test()
        print(f"PASS: {name}")
