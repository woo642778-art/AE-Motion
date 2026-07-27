#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import plistlib

BASE_FRAMEWORK_SHA256 = "ffedfaf18e993aef9d3ea2b4639dc39b197891db224fecc33c5f2e21c7d5f3b9"
PATCHED_FRAMEWORK_SHA256 = "54df320ffc7f467f1ad8c7b80619bcd223c20d088b443aadeddc0fbf383628bb"
BASE_PROMOTION_DYLIB_SHA256 = "78802c0d36762fbc86ac40346edf4b8970f152e3cba90a99b638867a9d813aae"
PATCHED_PROMOTION_DYLIB_SHA256 = "781307fb0356d86d3d66bf534cdd06b5cc2824648f44cf868dc9257e9fe12793"
BASE_INFO_PLIST_SHA256 = "6ee916845385144241e5a2d9bc3a93cd7fa254b45359a34a6c7d1112d96d1393"
PATCHED_INFO_PLIST_SHA256 = "ea7fdb5e3780fd40533971e8e815b89ce8d4f3b881f64327f716e3c29c88a329"

FRAMEWORK_GUARD_OFFSET = 0x0A1BE0
FRAMEWORK_GUARD_BYTES = bytes.fromhex(
    "f353bea9fe0b00f9e10f00f9f30300aa682200b0013140f982e90d94200100b4"
    "f40300aa682200b001a946f9e00314aa7ce90d941f0013eb810200540d000014"
    "682200d0011d40f9e00313aa75e90d94000100b4f40300aa682200b001a546f9"
    "e00314aa6fe90d941f0013ebe1000054fe0b40f9e10f40f9e00313aaf353c2a8"
    "ff8302d147af0714fe0b40f9f353c2a8c0035fd6"
)
FRAMEWORK_BRANCH_OFFSET = 0x28D97C
FRAMEWORK_ORIGINAL_BRANCH = bytes.fromhex("ff8302d1")
FRAMEWORK_PATCHED_BRANCH = bytes.fromhex("9950f817")
PROMOTION_OLD_URL = b"https://t.me/blatants"
PROMOTION_NEW_URL = b"https://t.me/aemotionios"
PROMOTION_REPLACEMENT = b"AE Motion iOS channel: https://t.me/aemotionios | Official community   "
PROMOTION_EXPECTED_COUNT = 1724


class KnownFixError(RuntimeError):
    pass


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def patch_extension_framework(data: bytes) -> bytes:
    digest = _sha256(data)
    if digest == PATCHED_FRAMEWORK_SHA256:
        return data
    if digest != BASE_FRAMEWORK_SHA256:
        raise KnownFixError(f"unexpected extension framework SHA-256: {digest}")
    if data[FRAMEWORK_BRANCH_OFFSET:FRAMEWORK_BRANCH_OFFSET + 4] != FRAMEWORK_ORIGINAL_BRANCH:
        raise KnownFixError("extension framework branch site does not match baseline")
    patched = bytearray(data)
    patched[FRAMEWORK_GUARD_OFFSET:FRAMEWORK_GUARD_OFFSET + len(FRAMEWORK_GUARD_BYTES)] = FRAMEWORK_GUARD_BYTES
    patched[FRAMEWORK_BRANCH_OFFSET:FRAMEWORK_BRANCH_OFFSET + 4] = FRAMEWORK_PATCHED_BRANCH
    result = bytes(patched)
    if _sha256(result) != PATCHED_FRAMEWORK_SHA256:
        raise KnownFixError("extension framework patch hash mismatch")
    return result


def patch_promotion_dylib(data: bytes) -> bytes:
    digest = _sha256(data)
    if digest == PATCHED_PROMOTION_DYLIB_SHA256:
        return data
    if digest != BASE_PROMOTION_DYLIB_SHA256:
        raise KnownFixError(f"unexpected promotion dylib SHA-256: {digest}")

    output = bytearray(data)
    cursor = 0
    count = 0
    while True:
        position = data.find(PROMOTION_OLD_URL, cursor)
        if position < 0:
            break
        start = data.rfind(b"\0", 0, position) + 1
        end = data.find(b"\0", position)
        if end < 0:
            raise KnownFixError("unterminated promotion string")
        original = data[start:end]
        if len(original) != len(PROMOTION_REPLACEMENT):
            raise KnownFixError(f"unexpected promotion string length at {start}: {len(original)}")
        output[start:end] = PROMOTION_REPLACEMENT
        count += 1
        cursor = end + 1

    if count != PROMOTION_EXPECTED_COUNT:
        raise KnownFixError(f"expected {PROMOTION_EXPECTED_COUNT} promotion strings, found {count}")
    result = bytes(output)
    if PROMOTION_OLD_URL in result or result.count(PROMOTION_NEW_URL) != PROMOTION_EXPECTED_COUNT:
        raise KnownFixError("promotion URL replacement verification failed")
    if _sha256(result) != PATCHED_PROMOTION_DYLIB_SHA256:
        raise KnownFixError("promotion dylib patch hash mismatch")
    return result


def patch_info_plist(data: bytes) -> bytes:
    digest = _sha256(data)
    if digest == PATCHED_INFO_PLIST_SHA256:
        return data
    if digest != BASE_INFO_PLIST_SHA256:
        raise KnownFixError(f"unexpected app Info.plist SHA-256: {digest}")
    value = plistlib.loads(data)
    value["@IPAdecryptBot"] = "by https://t.me/aemotionios"
    result = plistlib.dumps(value, fmt=plistlib.FMT_XML, sort_keys=True)
    if _sha256(result) != PATCHED_INFO_PLIST_SHA256:
        raise KnownFixError("Info.plist patch hash mismatch")
    return result
