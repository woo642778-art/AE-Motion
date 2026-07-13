#!/usr/bin/env python3
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
CORE = ROOT / 'Sources/AEMotionExtensionsCore/ToolPlacement.swift'
PROXY = ROOT / 'Sources/AEMotionExtensionsHost/CategoryCollectionProxy.swift'
TESTS = ROOT / 'Tests/AEMotionExtensionsCoreTests/CoreTests.swift'

core = CORE.read_text(encoding='utf-8')
proxy = PROXY.read_text(encoding='utf-8')
tests = TESTS.read_text(encoding='utf-8')

checks = {
    'host imports core forwarding policy': r'import\s+AEMotionExtensionsCore',
    'forwarding policy exists': r'public\s+enum\s+CollectionProxyForwardingPolicy',
    'policy rejects index-path selectors': r'range\(of:\s*"indexpath"\s*,\s*options:\s*\.caseInsensitive\)\s*==\s*nil',
    'proxy has synthetic path detector': r'private\s+func\s+isSyntheticPath\s*\(',
    'will-display callback is intercepted': r'willDisplay\s+cell:\s*UICollectionViewCell',
    'end-display callback is intercepted': r'didEndDisplaying\s+cell:\s*UICollectionViewCell',
    'synthetic callbacks are suppressed': r'guard\s+!isSyntheticPath\(indexPath\)\s+else\s*\{\s*return\s*\}',
    'responds uses forwarding policy': r'CollectionProxyForwardingPolicy\.mayForward\(selectorName:\s*selectorName\)',
    'forwardingTarget uses forwarding policy': r'override\s+nonisolated\s+func\s+forwardingTarget[\s\S]*CollectionProxyForwardingPolicy\.mayForward',
    'core regression test covers will display': r'testCategoryProxyDoesNotForwardUnknownIndexPathSelectors[\s\S]*willDisplayCell',
}

failed = []
for name, pattern in checks.items():
    haystack = core if name.startswith('forwarding policy') or name.startswith('policy rejects') else tests if name.startswith('core regression') else proxy
    ok = re.search(pattern, haystack) is not None
    print(f"{'PASS' if ok else 'FAIL'}: {name}")
    if not ok:
        failed.append(name)

if proxy.count('CollectionProxyForwardingPolicy.mayForward(selectorName: selectorName)') < 2:
    print('FAIL: policy is enforced in both responds and forwardingTarget')
    failed.append('policy is enforced in both responds and forwardingTarget')
else:
    print('PASS: policy is enforced in both responds and forwardingTarget')

if proxy.count('guard !isSyntheticPath(indexPath) else { return }') < 4:
    print('FAIL: synthetic index paths are suppressed in explicit callbacks')
    failed.append('synthetic index paths are suppressed in explicit callbacks')
else:
    print('PASS: synthetic index paths are suppressed in explicit callbacks')

if failed:
    raise SystemExit('Category proxy index-path forwarding regression failed: ' + ', '.join(failed))
