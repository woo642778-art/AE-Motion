#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
from pathlib import Path
import shutil
import sys
import tempfile
import zipfile

EXPECTED_INPUT_SHA256 = "0a50dbd701751bc91dc7e7b38649c7aefbccf8853c0b8fc7336bc8f61a0d202c"
RETURN_INSTRUCTION = bytes.fromhex("c0035fd6")

PATCHES = {
    "Payload/AlightMotion.app/Frameworks/AEMotionExtensionsHost.framework/AEMotionExtensionsHost": {
        "offset": 0x190CB0,
        "expected": bytes.fromhex("eb2bb86d"),
        "symbol": "AEMotionLaunchOverlay.showWhenWindowAvailable(attempt:)",
    },
    "Payload/AlightMotion.app/Frameworks/AEMotionUI272.framework/AEMotionUI272": {
        "offset": 0x1A548,
        "expected": bytes.fromhex("e923b96d"),
        "symbol": "AEMotionLaunchOverlay.install()",
    },
}


class HotfixError(RuntimeError):
    pass


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def patched_binary(data: bytes, *, path: str, offset: int, expected: bytes, symbol: str) -> bytes:
    end = offset + len(expected)
    if end > len(data):
        raise HotfixError(f"{path}: {symbol} offset lies outside the Mach-O binary")
    actual = data[offset:end]
    if actual == RETURN_INSTRUCTION:
        raise HotfixError(f"{path}: {symbol} is already disabled")
    if actual != expected:
        raise HotfixError(
            f"{path}: unexpected bytes for {symbol} at 0x{offset:x}: "
            f"expected {expected.hex()}, found {actual.hex()}"
        )
    result = bytearray(data)
    result[offset:end] = RETURN_INSTRUCTION
    return bytes(result)


def write_hotfix(source: Path, output: Path) -> None:
    source_hash = sha256_file(source)
    if source_hash != EXPECTED_INPUT_SHA256:
        raise HotfixError(
            "input IPA is not the verified Build 847 candidate: "
            f"expected {EXPECTED_INPUT_SHA256}, found {source_hash}"
        )

    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="aemotion-build847-hotfix-") as temp_dir:
        temporary_output = Path(temp_dir) / output.name
        with zipfile.ZipFile(source, "r") as input_zip, zipfile.ZipFile(
            temporary_output,
            "w",
            allowZip64=True,
        ) as output_zip:
            names = set(input_zip.namelist())
            missing = sorted(set(PATCHES) - names)
            if missing:
                raise HotfixError("required framework entries are missing: " + ", ".join(missing))

            for info in input_zip.infolist():
                data = input_zip.read(info.filename)
                patch = PATCHES.get(info.filename)
                if patch is not None:
                    data = patched_binary(data, path=info.filename, **patch)
                output_zip.writestr(info, data)

        verify_hotfix(source, temporary_output)
        shutil.move(temporary_output, output)


def verify_hotfix(source: Path, output: Path) -> None:
    with zipfile.ZipFile(source, "r") as before, zipfile.ZipFile(output, "r") as after:
        before_names = before.namelist()
        after_names = after.namelist()
        if before_names != after_names:
            raise HotfixError("archive entry order or membership changed")

        for name in before_names:
            original = before.read(name)
            patched = after.read(name)
            patch = PATCHES.get(name)
            if patch is None:
                if patched != original:
                    raise HotfixError(f"non-target entry changed: {name}")
                continue

            if len(patched) != len(original):
                raise HotfixError(f"target binary size changed: {name}")
            offset = patch["offset"]
            expected = patch["expected"]
            if original[offset:offset + 4] != expected:
                raise HotfixError(f"source verification failed for {name}")
            if patched[offset:offset + 4] != RETURN_INSTRUCTION:
                raise HotfixError(f"launch overlay remains active in {name}")
            differences = [
                index
                for index, (left, right) in enumerate(zip(original, patched))
                if left != right
            ]
            expected_differences = [
                offset + index
                for index, (left, right) in enumerate(zip(expected, RETURN_INSTRUCTION))
                if left != right
            ]
            if differences != expected_differences:
                raise HotfixError(
                    f"unexpected binary changes in {name}: "
                    f"expected {expected_differences}, found {differences[:16]}"
                )

        bad = after.testzip()
        if bad is not None:
            raise HotfixError(f"ZIP CRC verification failed at {bad}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Disable only the two Build 847 launch overlay entry points that can "
            "hold the app on the infinite-loading screen."
        )
    )
    parser.add_argument("input_ipa", type=Path)
    parser.add_argument("output_ipa", type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.input_ipa.resolve() == args.output_ipa.resolve():
        raise HotfixError("input and output paths must differ")
    write_hotfix(args.input_ipa, args.output_ipa)
    print(f"input_sha256={sha256_file(args.input_ipa)}")
    print(f"output_sha256={sha256_file(args.output_ipa)}")
    for name, patch in PATCHES.items():
        print(f"disabled={patch['symbol']} path={name} offset=0x{patch['offset']:x}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except HotfixError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        raise SystemExit(1)
