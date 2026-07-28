#!/usr/bin/env python3
from __future__ import annotations

from dataclasses import dataclass
import struct

MH_MAGIC_64 = 0xFEEDFACF
CPU_TYPE_ARM64 = 0x0100000C
LC_SEGMENT_64 = 0x19
LC_LOAD_DYLIB = 0x0C
LC_LOAD_WEAK_DYLIB = 0x80000018
LC_REEXPORT_DYLIB = 0x8000001F
LC_LOAD_UPWARD_DYLIB = 0x80000023
DYLIB_COMMANDS = {
    LC_LOAD_DYLIB,
    LC_LOAD_WEAK_DYLIB,
    LC_REEXPORT_DYLIB,
    LC_LOAD_UPWARD_DYLIB,
}
HEADER_SIZE_64 = 32
SECTION_SIZE_64 = 80
SEGMENT_COMMAND_SIZE_64 = 72


class MachOError(RuntimeError):
    pass


@dataclass(frozen=True)
class LoadCommand:
    cmd: int
    cmdsize: int
    offset: int
    payload: bytes


@dataclass(frozen=True)
class MachOInfo:
    ncmds: int
    sizeofcmds: int
    command_end: int
    first_section_offset: int
    dylib_paths: tuple[str, ...]
    commands: tuple[LoadCommand, ...]


def _align(value: int, alignment: int = 8) -> int:
    return (value + alignment - 1) & ~(alignment - 1)


def _read_c_string(data: bytes, start: int, end: int) -> str:
    if start < 0 or start >= end or end > len(data):
        raise MachOError("invalid Mach-O string range")
    raw = data[start:end].split(b"\0", 1)[0]
    try:
        return raw.decode("utf-8")
    except UnicodeDecodeError as error:
        raise MachOError("invalid UTF-8 dylib path") from error


def inspect_macho(binary: bytes) -> MachOInfo:
    if len(binary) < HEADER_SIZE_64:
        raise MachOError("Mach-O is smaller than mach_header_64")
    magic, cputype, _cpusubtype, _filetype, ncmds, sizeofcmds, _flags, _reserved = struct.unpack_from(
        "<IiiIIIII", binary, 0
    )
    if magic != MH_MAGIC_64:
        raise MachOError("expected a thin little-endian 64-bit Mach-O")
    if cputype != CPU_TYPE_ARM64:
        raise MachOError("expected a thin arm64 Mach-O")
    command_end = HEADER_SIZE_64 + sizeofcmds
    if command_end > len(binary):
        raise MachOError("load commands exceed file size")

    commands: list[LoadCommand] = []
    dylib_paths: list[str] = []
    first_section_offset: int | None = None
    cursor = HEADER_SIZE_64

    for _ in range(ncmds):
        if cursor + 8 > command_end:
            raise MachOError("truncated load command header")
        cmd, cmdsize = struct.unpack_from("<II", binary, cursor)
        if cmdsize < 8 or cmdsize % 4 != 0:
            raise MachOError("invalid load command size")
        next_cursor = cursor + cmdsize
        if next_cursor > command_end:
            raise MachOError("load command exceeds sizeofcmds")
        payload = binary[cursor:next_cursor]
        commands.append(LoadCommand(cmd=cmd, cmdsize=cmdsize, offset=cursor, payload=payload))

        if cmd == LC_SEGMENT_64:
            if cmdsize < SEGMENT_COMMAND_SIZE_64:
                raise MachOError("truncated LC_SEGMENT_64")
            nsects = struct.unpack_from("<I", binary, cursor + 64)[0]
            expected_minimum = SEGMENT_COMMAND_SIZE_64 + nsects * SECTION_SIZE_64
            if cmdsize < expected_minimum:
                raise MachOError("LC_SEGMENT_64 sections exceed command size")
            section_cursor = cursor + SEGMENT_COMMAND_SIZE_64
            for _section_index in range(nsects):
                section_offset = struct.unpack_from("<I", binary, section_cursor + 48)[0]
                section_size = struct.unpack_from("<Q", binary, section_cursor + 40)[0]
                if section_offset > 0 and section_size > 0:
                    if first_section_offset is None or section_offset < first_section_offset:
                        first_section_offset = section_offset
                section_cursor += SECTION_SIZE_64

        if cmd in DYLIB_COMMANDS:
            if cmdsize < 24:
                raise MachOError("truncated dylib command")
            name_offset = struct.unpack_from("<I", binary, cursor + 8)[0]
            if name_offset < 24 or name_offset >= cmdsize:
                raise MachOError("invalid dylib name offset")
            dylib_paths.append(_read_c_string(binary, cursor + name_offset, next_cursor))

        cursor = next_cursor

    if cursor != command_end:
        raise MachOError("ncmds does not consume sizeofcmds exactly")
    if first_section_offset is None:
        raise MachOError("no file-backed Mach-O section found")
    if first_section_offset < command_end:
        raise MachOError("first section overlaps load commands")

    return MachOInfo(
        ncmds=ncmds,
        sizeofcmds=sizeofcmds,
        command_end=command_end,
        first_section_offset=first_section_offset,
        dylib_paths=tuple(dylib_paths),
        commands=tuple(commands),
    )


def _command_dylib_path(command: LoadCommand) -> str | None:
    if command.cmd not in DYLIB_COMMANDS or command.cmdsize < 24:
        return None
    name_offset = struct.unpack_from("<I", command.payload, 8)[0]
    return _read_c_string(command.payload, name_offset, command.cmdsize)


def make_load_dylib_command(dylib_path: str) -> bytes:
    if not dylib_path or "\0" in dylib_path:
        raise MachOError("invalid dylib path")
    encoded = dylib_path.encode("utf-8") + b"\0"
    cmdsize = _align(24 + len(encoded), 8)
    command = bytearray(cmdsize)
    struct.pack_into("<IIIIII", command, 0, LC_LOAD_DYLIB, cmdsize, 24, 0, 0, 0)
    command[24:24 + len(encoded)] = encoded
    return bytes(command)


def append_load_dylib(binary: bytes, dylib_path: str) -> bytes:
    info = inspect_macho(binary)
    occurrences = info.dylib_paths.count(dylib_path)
    if occurrences == 1:
        return binary
    if occurrences > 1:
        raise MachOError("dylib path already appears more than once")

    command = make_load_dylib_command(dylib_path)
    new_end = info.command_end + len(command)
    if new_end > info.first_section_offset:
        raise MachOError("insufficient Mach-O load-command padding")
    padding = binary[info.command_end:new_end]
    if any(padding):
        raise MachOError("load-command padding is not zero-filled")

    patched = bytearray(binary)
    patched[info.command_end:new_end] = command
    struct.pack_into("<I", patched, 16, info.ncmds + 1)
    struct.pack_into("<I", patched, 20, info.sizeofcmds + len(command))

    result = bytes(patched)
    updated = inspect_macho(result)
    if updated.dylib_paths.count(dylib_path) != 1:
        raise MachOError("new dylib command verification failed")
    if result[info.first_section_offset:] != binary[info.first_section_offset:]:
        raise MachOError("executable section bytes changed")
    for before, after in zip(info.commands, updated.commands[: len(info.commands)]):
        if before.payload != after.payload:
            raise MachOError("an existing load command changed")
    return result


def insert_load_dylib_before(binary: bytes, dylib_path: str, before_path: str) -> bytes:
    info = inspect_macho(binary)
    occurrences = info.dylib_paths.count(dylib_path)
    if occurrences > 1:
        raise MachOError("dylib path already appears more than once")
    if info.dylib_paths.count(before_path) != 1:
        raise MachOError("reference dylib path must appear exactly once")
    if occurrences == 1:
        if info.dylib_paths.index(dylib_path) < info.dylib_paths.index(before_path):
            return binary
        raise MachOError("existing dylib is not before the reference dylib")

    target = next(
        command for command in info.commands
        if _command_dylib_path(command) == before_path
    )
    command = make_load_dylib_command(dylib_path)
    new_end = info.command_end + len(command)
    if new_end > info.first_section_offset:
        raise MachOError("insufficient Mach-O load-command padding")
    if any(binary[info.command_end:new_end]):
        raise MachOError("load-command padding is not zero-filled")

    patched = bytearray(binary)
    retained_tail = binary[target.offset:info.command_end]
    patched[target.offset:target.offset + len(command)] = command
    patched[target.offset + len(command):new_end] = retained_tail
    struct.pack_into("<I", patched, 16, info.ncmds + 1)
    struct.pack_into("<I", patched, 20, info.sizeofcmds + len(command))

    result = bytes(patched)
    updated = inspect_macho(result)
    if updated.dylib_paths.count(dylib_path) != 1:
        raise MachOError("inserted dylib command verification failed")
    if updated.dylib_paths.index(dylib_path) >= updated.dylib_paths.index(before_path):
        raise MachOError("inserted dylib command is not before the reference dylib")
    if result[info.first_section_offset:] != binary[info.first_section_offset:]:
        raise MachOError("executable section bytes changed")

    expected_payloads: list[bytes] = []
    for existing in info.commands:
        if existing is target:
            expected_payloads.append(command)
        expected_payloads.append(existing.payload)
    actual_payloads = [existing.payload for existing in updated.commands]
    if actual_payloads != expected_payloads:
        raise MachOError("non-target load commands changed during insertion")
    return result


def remove_load_dylib(binary: bytes, dylib_path: str) -> bytes:
    info = inspect_macho(binary)
    matching = [command for command in info.commands if _command_dylib_path(command) == dylib_path]
    if not matching:
        return binary
    if len(matching) != 1:
        raise MachOError("dylib path appears more than once")

    target = matching[0]
    retained = [command.payload for command in info.commands if command is not target]
    new_commands = b"".join(retained)
    new_sizeofcmds = len(new_commands)
    new_end = HEADER_SIZE_64 + new_sizeofcmds
    if new_end > info.first_section_offset:
        raise MachOError("rebuilt load commands overlap first section")

    patched = bytearray(binary)
    patched[HEADER_SIZE_64:info.command_end] = b"\0" * info.sizeofcmds
    patched[HEADER_SIZE_64:new_end] = new_commands
    struct.pack_into("<I", patched, 16, info.ncmds - 1)
    struct.pack_into("<I", patched, 20, new_sizeofcmds)

    result = bytes(patched)
    updated = inspect_macho(result)
    if dylib_path in updated.dylib_paths:
        raise MachOError("removed dylib command is still present")
    if result[info.first_section_offset:] != binary[info.first_section_offset:]:
        raise MachOError("executable section bytes changed")

    expected = [command.payload for command in info.commands if command is not target]
    actual = [command.payload for command in updated.commands]
    if actual != expected:
        raise MachOError("non-target load commands changed")
    return result
