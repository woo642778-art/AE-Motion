#!/usr/bin/env python3
from __future__ import annotations

import struct
import unittest
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from macho_load_command import (  # noqa: E402
    CPU_TYPE_ARM64,
    HEADER_SIZE_64,
    LC_SEGMENT_64,
    MH_MAGIC_64,
    MachOError,
    append_load_dylib,
    inspect_macho,
)

PATH = "@rpath/AEMotionUI272.framework/AEMotionUI272"


def make_fixture(*, padding_byte: int = 0, first_section_offset: int = 512) -> bytes:
    segment_size = 72 + 80
    segment = bytearray(segment_size)
    struct.pack_into("<II", segment, 0, LC_SEGMENT_64, segment_size)
    segment[8:14] = b"__TEXT"
    struct.pack_into("<QQQQiiII", segment, 24, 0, 4096, 0, 4096, 5, 5, 1, 0)
    section = 72
    segment[section:section + 6] = b"__text"
    segment[section + 16:section + 22] = b"__TEXT"
    struct.pack_into("<QQIIIIIIII", segment, section + 32, 4096, 64, first_section_offset, 2, 0, 0, 0, 0, 0, 0)

    data = bytearray(first_section_offset + 64)
    struct.pack_into("<IiiIIIII", data, 0, MH_MAGIC_64, CPU_TYPE_ARM64, 0, 2, 1, len(segment), 0, 0)
    data[HEADER_SIZE_64:HEADER_SIZE_64 + len(segment)] = segment
    command_end = HEADER_SIZE_64 + len(segment)
    data[command_end:first_section_offset] = bytes([padding_byte]) * (first_section_offset - command_end)
    data[first_section_offset:] = b"T" * 64
    return bytes(data)


class MachOLoadCommandTests(unittest.TestCase):
    def test_appends_one_command_without_changing_sections(self) -> None:
        original = make_fixture()
        before = inspect_macho(original)
        patched = append_load_dylib(original, PATH)
        after = inspect_macho(patched)
        self.assertEqual(after.ncmds, before.ncmds + 1)
        self.assertGreater(after.sizeofcmds, before.sizeofcmds)
        self.assertEqual(after.dylib_paths.count(PATH), 1)
        self.assertEqual(patched[before.first_section_offset:], original[before.first_section_offset:])
        self.assertEqual(after.commands[0].payload, before.commands[0].payload)

    def test_duplicate_insertion_is_idempotent(self) -> None:
        once = append_load_dylib(make_fixture(), PATH)
        twice = append_load_dylib(once, PATH)
        self.assertEqual(twice, once)

    def test_rejects_nonzero_padding(self) -> None:
        with self.assertRaisesRegex(MachOError, "zero-filled"):
            append_load_dylib(make_fixture(padding_byte=1), PATH)

    def test_rejects_insufficient_padding(self) -> None:
        fixture = make_fixture(first_section_offset=HEADER_SIZE_64 + 72 + 80 + 8)
        with self.assertRaisesRegex(MachOError, "insufficient"):
            append_load_dylib(fixture, PATH)


if __name__ == "__main__":
    unittest.main(verbosity=2)
