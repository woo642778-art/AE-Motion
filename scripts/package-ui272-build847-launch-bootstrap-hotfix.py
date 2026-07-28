#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path
import shutil
import struct
import sys
import tempfile
import zipfile

from macho_load_command import inspect_macho

EXPECTED_INPUT_SHA256 = "0a50dbd701751bc91dc7e7b38649c7aefbccf8853c0b8fc7336bc8f61a0d202c"
UI = "@rpath/AEMotionUI272.framework/AEMotionUI272"
LEGACY = "@rpath/AlightMotion.dylib"
PROMOTION = "@rpath/blatantsPatch.dylib"
HOST = "@rpath/AEMotionExtensionsHost.framework/AEMotionExtensionsHost"
EXPECTED_BEFORE = (UI, LEGACY, PROMOTION, HOST)
EXPECTED_AFTER = (LEGACY, PROMOTION, UI, HOST)
RETURN = bytes.fromhex("c0035fd6")
UI_OVERLAY_ENTRY = 0x1A548
HOST_OVERLAY_ENTRY = 0x190CB0
TELEGRAM_TOKENS = (
    b"https://t.me/aemotionios",
    b"Join AE Motion Telegram",
    b"Continue to AE Motion",
    b"aemotion.build847.official-channel-dismissed",
)


class HotfixError(RuntimeError):
    pass


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def command_path(payload: bytes) -> str | None:
    cmd, size = struct.unpack_from("<II", payload, 0)
    if cmd not in {0x0C, 0x80000018, 0x8000001F, 0x80000023}:
        return None
    if size != len(payload) or size < 24:
        raise HotfixError("invalid dylib load command")
    name_offset = struct.unpack_from("<I", payload, 8)[0]
    if name_offset < 24 or name_offset >= size:
        raise HotfixError("invalid dylib path offset")
    return payload[name_offset:size].split(b"\0", 1)[0].decode("utf-8")


def relevant_order(binary: bytes) -> tuple[str, ...]:
    relevant = {UI, LEGACY, PROMOTION, HOST}
    return tuple(
        path
        for command in inspect_macho(binary).commands
        if (path := command_path(command.payload)) in relevant
    )


def reorder_launch_commands(binary: bytes) -> bytes:
    before = inspect_macho(binary)
    if relevant_order(binary) != EXPECTED_BEFORE:
        raise HotfixError(f"unexpected Build 847 load order: {relevant_order(binary)!r}")

    commands = list(before.commands)
    target = {
        path: [command for command in commands if command_path(command.payload) == path]
        for path in EXPECTED_BEFORE
    }
    if any(len(matches) != 1 for matches in target.values()):
        raise HotfixError("required launch load command is missing or duplicated")

    ui_command = target[UI][0]
    host_command = target[HOST][0]
    commands.remove(ui_command)
    commands.insert(commands.index(host_command), ui_command)
    rebuilt = b"".join(command.payload for command in commands)
    if len(rebuilt) != before.sizeofcmds:
        raise HotfixError("load-command region size changed")

    patched = bytearray(binary)
    patched[32:before.command_end] = rebuilt
    result = bytes(patched)
    after = inspect_macho(result)
    if relevant_order(result) != EXPECTED_AFTER:
        raise HotfixError("repaired launch order is incorrect")
    if (after.ncmds, after.sizeofcmds) != (before.ncmds, before.sizeofcmds):
        raise HotfixError("Mach-O command counts changed")
    if result[before.first_section_offset:] != binary[before.first_section_offset:]:
        raise HotfixError("main executable section bytes changed")
    if sorted(command.payload for command in after.commands) != sorted(
        command.payload for command in before.commands
    ):
        raise HotfixError("load-command payload set changed")
    return result


def clone_info(info: zipfile.ZipInfo) -> zipfile.ZipInfo:
    clone = zipfile.ZipInfo(info.filename, info.date_time)
    for name in (
        "compress_type", "comment", "extra", "internal_attr", "external_attr",
        "create_system", "create_version", "extract_version", "flag_bits", "volume",
    ):
        setattr(clone, name, getattr(info, name))
    return clone


def app_paths(archive: zipfile.ZipFile) -> tuple[str, str, str]:
    apps = sorted({
        name.split("/")[1]
        for name in archive.namelist()
        if name.startswith("Payload/") and ".app/" in name
    })
    if len(apps) != 1:
        raise HotfixError("expected exactly one app bundle")
    prefix = f"Payload/{apps[0]}/"
    return (
        prefix + "AlightMotion",
        prefix + "Frameworks/AEMotionUI272.framework/AEMotionUI272",
        prefix + "Frameworks/AEMotionExtensionsHost.framework/AEMotionExtensionsHost",
    )


def verify_hotfix(source: Path, output: Path) -> None:
    with zipfile.ZipFile(source) as before, zipfile.ZipFile(output) as after:
        before_infos, after_infos = before.infolist(), after.infolist()
        if [i.filename for i in before_infos] != [i.filename for i in after_infos]:
            raise HotfixError("archive membership or order changed")
        main, ui, host = app_paths(before)
        original_ui, original_host = before.read(ui), before.read(host)
        if not all(token in original_ui for token in TELEGRAM_TOKENS):
            raise HotfixError("official Telegram page is missing")
        if original_ui[UI_OVERLAY_ENTRY:UI_OVERLAY_ENTRY + 4] == RETURN:
            raise HotfixError("UI launch overlay was disabled")
        if original_host[HOST_OVERLAY_ENTRY:HOST_OVERLAY_ENTRY + 4] == RETURN:
            raise HotfixError("host launch overlay was disabled")
        if after.read(ui) != original_ui or after.read(host) != original_host:
            raise HotfixError("Telegram or overlay framework bytes changed")

        for left, right in zip(before_infos, after_infos):
            metadata = lambda i: (
                i.date_time, i.compress_type, i.external_attr, i.internal_attr,
                i.create_system, i.extra, i.comment,
            )
            if metadata(left) != metadata(right):
                raise HotfixError(f"ZIP metadata changed: {left.filename}")
            if left.filename != main and before.read(left.filename) != after.read(right.filename):
                raise HotfixError(f"non-main IPA entry changed: {left.filename}")

        original_main, repaired_main = before.read(main), after.read(main)
        if relevant_order(original_main) != EXPECTED_BEFORE:
            raise HotfixError("source launch order changed")
        if relevant_order(repaired_main) != EXPECTED_AFTER:
            raise HotfixError("output launch order was not repaired")
        first_section = inspect_macho(original_main).first_section_offset
        if repaired_main[first_section:] != original_main[first_section:]:
            raise HotfixError("main executable section bytes changed")
        if after.testzip() is not None:
            raise HotfixError("ZIP CRC verification failed")


def write_hotfix(source: Path, output: Path) -> None:
    actual = sha256_file(source)
    if actual != EXPECTED_INPUT_SHA256:
        raise HotfixError(
            f"input IPA SHA-256 mismatch: expected {EXPECTED_INPUT_SHA256}, found {actual}"
        )
    if source.resolve() == output.resolve():
        raise HotfixError("input and output paths must differ")

    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="aemotion-build847-bootstrap-") as directory:
        temporary = Path(directory) / output.name
        with zipfile.ZipFile(source) as src, zipfile.ZipFile(temporary, "w", allowZip64=True) as dst:
            main, _ui, _host = app_paths(src)
            repaired_main = reorder_launch_commands(src.read(main))
            for info in src.infolist():
                dst.writestr(clone_info(info), repaired_main if info.filename == main else src.read(info.filename))
        verify_hotfix(source, temporary)
        shutil.move(temporary, output)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Repair Build 847 launch order without removing the official Telegram page."
    )
    parser.add_argument("input_ipa", type=Path)
    parser.add_argument("output_ipa", type=Path)
    args = parser.parse_args()
    write_hotfix(args.input_ipa, args.output_ipa)
    print(f"input_sha256={sha256_file(args.input_ipa)}")
    print(f"output_sha256={sha256_file(args.output_ipa)}")
    print("telegram_page_preserved=true")
    print("framework_bytes_preserved=true")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except HotfixError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        raise SystemExit(1)
