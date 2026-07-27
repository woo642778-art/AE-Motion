#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import zipfile

BASE_IPA_SHA256 = "f72053a38a64ea2dac48e18d248d1b279755e24e0318724015b4fd9356090a6d"
EXPECTED = {
    "Payload/AlightMotion.app/AlightMotion": "21576328f5bd3a28ecce882b855159d354610add5415c54a6187c83879b577fe",
    "Payload/AlightMotion.app/Frameworks/AlightMotion.dylib": "78802c0d36762fbc86ac40346edf4b8970f152e3cba90a99b638867a9d813aae",
    "Payload/AlightMotion.app/Frameworks/AEMotionExtensionsHost.framework/AEMotionExtensionsHost": "ffedfaf18e993aef9d3ea2b4639dc39b197891db224fecc33c5f2e21c7d5f3b9",
    "Payload/AlightMotion.app/Frameworks/AEMotionExtensionsHost.framework/Info.plist": "f9d9174ff039fde803031261bbf8f8108087610faff0f7a27168cc80eaa0e5ad",
    "Payload/AlightMotion.app/Info.plist": "6ee916845385144241e5a2d9bc3a93cd7fa254b45359a34a6c7d1112d96d1393",
}
FEATURE_MARKERS = (
    b"AEMotionHome",
    b"Editing Asset Library",
    b"3D Studio",
    b"World Studio",
    b"https://www.tiktok.com/@ss09102?",
)


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def verify(path: Path) -> dict[str, object]:
    digest = sha256_file(path)
    if digest != BASE_IPA_SHA256:
        raise RuntimeError(f"baseline IPA SHA-256 mismatch: {digest}")
    report: dict[str, object] = {"ipaSHA256": digest, "files": {}}
    with zipfile.ZipFile(path) as archive:
        if archive.testzip() is not None:
            raise RuntimeError("baseline ZIP CRC failed")
        for name, expected_hash in EXPECTED.items():
            data = archive.read(name)
            actual = sha256_bytes(data)
            if actual != expected_hash:
                raise RuntimeError(f"baseline file hash mismatch: {name}: {actual}")
            report["files"][name] = actual
        framework = archive.read(
            "Payload/AlightMotion.app/Frameworks/AEMotionExtensionsHost.framework/AEMotionExtensionsHost"
        )
        app_info = archive.read("Payload/AlightMotion.app/Info.plist")
        promotion = archive.read("Payload/AlightMotion.app/Frameworks/AlightMotion.dylib")
        marker_blob = framework + b"\0" + app_info + b"\0" + promotion
        missing = [marker.decode("utf-8") for marker in FEATURE_MARKERS if marker not in marker_blob]
        if missing:
            raise RuntimeError("missing baseline feature markers: " + ", ".join(missing))
        if promotion.count(b"https://t.me/blatants") != 1724:
            raise RuntimeError("baseline promotion string count changed")
        if b"by https://t.me/hiepkimcdtk55" not in app_info:
            raise RuntimeError("baseline Info.plist promotion marker changed")
        report["featureMarkers"] = [marker.decode("utf-8") for marker in FEATURE_MARKERS]
        report["promotionOccurrences"] = 1724
    return report


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--baseline-ipa", type=Path, required=True)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    try:
        report = verify(args.baseline_ipa)
    except Exception as error:
        print(f"FAIL: {error}")
        return 1
    if args.json:
        print(json.dumps(report, indent=2, sort_keys=True))
    else:
        print("PASS: immutable AE Motion 2.7(2) baseline verified")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
