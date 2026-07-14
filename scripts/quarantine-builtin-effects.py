#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import shutil
import tempfile

QUARANTINE_STATUSES = {
    "existingBroken", "duplicate", "placeholder", "unsupportedDependency", "rejected"
}


def _load_report(path: Path) -> dict:
    report = json.loads(path.read_text(encoding="utf-8"))
    if report.get("schemaVersion") != 1 or not isinstance(report.get("records"), list):
        raise ValueError("Unsupported or malformed integrity report.")
    return report


def _manifest_entry(record: dict) -> dict:
    findings = record.get("findings") or []
    reason = record.get("quarantineReason") or (findings[0].get("code") if findings else record["status"])
    filename = record["fileName"]
    return {
        "effectID": record.get("effectID", ""),
        "originalPath": f"BuiltinEffects/{filename}",
        "quarantinePath": f"AEMotionQuarantine/BuiltinEffects/{filename}",
        "reason": reason,
        "status": record["status"],
        "descriptorSHA256": record.get("descriptorSHA256", ""),
    }


def quarantine(app: Path, report_path: Path, manifest_path: Path | None, mode: str) -> dict:
    app = app.resolve()
    if app.suffix != ".app" or not app.is_dir():
        raise FileNotFoundError(f"Expected an extracted .app directory: {app}")
    effects = app / "BuiltinEffects"
    report = _load_report(report_path)
    selected = [record for record in report["records"] if record.get("status") in QUARANTINE_STATUSES]

    sources: list[tuple[dict, Path]] = []
    for record in selected:
        filename = Path(record.get("fileName", ""))
        if filename.name != str(filename) or filename.suffix.lower() != ".xml":
            raise ValueError(f"Unsafe effect file name in report: {filename}")
        source = effects / filename.name
        if not source.is_file():
            raise FileNotFoundError(f"Reported effect does not exist: {source}")
        sources.append((record, source))

    manifest = {
        "schemaVersion": 1,
        "sourceReport": report_path.name,
        "quarantinedCount": len(sources),
        "entries": [_manifest_entry(record) for record, _ in sources],
    }
    if mode == "dry-run":
        for entry in manifest["entries"]:
            print(f"DRY-RUN {entry['originalPath']} -> {entry['quarantinePath']} ({entry['reason']})")
        return manifest

    final_quarantine = app / "AEMotionQuarantine"
    final_diagnostics = app / "AEMotionDiagnostics"
    if final_quarantine.exists() or final_diagnostics.exists():
        raise FileExistsError("Existing AE Motion diagnostics/quarantine directory must be removed before applying.")

    stage_root = Path(tempfile.mkdtemp(prefix=".aemotion-quarantine-", dir=app))
    staged_quarantine = stage_root / "AEMotionQuarantine" / "BuiltinEffects"
    staged_diagnostics = stage_root / "AEMotionDiagnostics"
    staged_quarantine.mkdir(parents=True)
    staged_diagnostics.mkdir(parents=True)

    try:
        for _, source in sources:
            shutil.copy2(source, staged_quarantine / source.name)
        shutil.copy2(report_path, staged_diagnostics / "effect-integrity.json")
        (staged_diagnostics / "quarantine-manifest.json").write_text(
            json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
        )
        if manifest_path:
            manifest_path.parent.mkdir(parents=True, exist_ok=True)
            manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")

        os.replace(stage_root / "AEMotionQuarantine", final_quarantine)
        os.replace(stage_root / "AEMotionDiagnostics", final_diagnostics)
        removed: list[Path] = []
        try:
            for _, source in sources:
                source.unlink()
                removed.append(source)
        except Exception:
            for source in removed:
                shutil.copy2(final_quarantine / "BuiltinEffects" / source.name, source)
            shutil.rmtree(final_quarantine, ignore_errors=True)
            shutil.rmtree(final_diagnostics, ignore_errors=True)
            raise
    finally:
        shutil.rmtree(stage_root, ignore_errors=True)

    print(f"Quarantined {len(sources)} effects.")
    return manifest


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("app", type=Path)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--manifest", type=Path)
    parser.add_argument("--mode", choices=("apply", "dry-run"), default="dry-run")
    args = parser.parse_args()
    quarantine(args.app, args.report, args.manifest, args.mode)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
