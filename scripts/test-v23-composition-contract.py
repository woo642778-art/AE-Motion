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


def test_structural_commit_requires_postcondition_verification() -> None:
    bridge = read("Sources/AEMotionExtensionsHost/CompositionHostBridge.swift")
    assert "verifyPostcondition" in bridge
    assert "nativeDocument == intent.finalDocument" in bridge
    assert "aemotionVerifyCompositionIntentJSON:" in bridge


def test_no_private_database_or_render_reimport_path() -> None:
    text = "\n".join(path.read_text(errors="ignore") for path in (ROOT / "Sources").rglob("*.swift")).lower()
    for forbidden in ["sqlite3_exec", "timeline.db", "project.db", "nspersistentstore", "avassetexportsession", "phphotolibrary"]:
        assert forbidden not in text
