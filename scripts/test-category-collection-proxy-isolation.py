#!/usr/bin/env python3
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'Sources/AEMotionExtensionsHost/CategoryCollectionProxy.swift'
text = SOURCE.read_text(encoding='utf-8')

required_patterns = {
    'data source forwarding reference is nonisolated unsafe': r'nonisolated\(unsafe\)\s+weak\s+var\s+originalDataSource\s*:\s*UICollectionViewDataSource\?',
    'delegate forwarding reference is nonisolated unsafe': r'nonisolated\(unsafe\)\s+weak\s+var\s+originalDelegate\s*:\s*UICollectionViewDelegate\?',
    'responds override is explicitly nonisolated': r'override\s+nonisolated\s+func\s+responds\s*\(',
    'forwarding override is explicitly nonisolated': r'override\s+nonisolated\s+func\s+forwardingTarget\s*\(',
}

failed = []
for name, pattern in required_patterns.items():
    ok = re.search(pattern, text) is not None
    print(f"{'PASS' if ok else 'FAIL'}: {name}")
    if not ok:
        failed.append(name)

# Compile a Swift 6 surrogate that exercises the exact actor-isolation pattern
# without requiring UIKit or the Objective-C runtime on the local host.
swift = r'''
protocol ForwardedObject: AnyObject {}

class RuntimeBase {
    nonisolated func responds() -> Bool { false }
    nonisolated func forwardingTarget() -> Any? { nil }
}

@MainActor
final class Proxy: RuntimeBase {
    nonisolated(unsafe) weak var originalDataSource: ForwardedObject?
    nonisolated(unsafe) weak var originalDelegate: ForwardedObject?

    init(dataSource: ForwardedObject?, delegate: ForwardedObject?) {
        self.originalDataSource = dataSource
        self.originalDelegate = delegate
    }

    override nonisolated func responds() -> Bool {
        let dataSource = originalDataSource
        let delegate = originalDelegate
        return super.responds() || dataSource != nil || delegate != nil
    }

    override nonisolated func forwardingTarget() -> Any? {
        let delegate = originalDelegate
        if delegate != nil { return delegate }
        return originalDataSource ?? super.forwardingTarget()
    }
}
'''
with tempfile.TemporaryDirectory() as directory:
    source = Path(directory) / 'proxy-isolation.swift'
    source.write_text(swift, encoding='utf-8')
    result = subprocess.run(
        ['swiftc', '-swift-version', '6', '-typecheck', str(source)],
        capture_output=True,
        text=True,
    )
    ok = result.returncode == 0
    print(f"{'PASS' if ok else 'FAIL'}: Swift 6 surrogate type-check")
    if not ok:
        print(result.stdout)
        print(result.stderr)
        failed.append('Swift 6 surrogate type-check')

if failed:
    raise SystemExit('CategoryCollectionProxy isolation regression failed: ' + ', '.join(failed))
