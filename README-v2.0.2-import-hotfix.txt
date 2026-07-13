AE Motion Extensions v2.0.2 — Core Import Build Hotfix

Root cause
- CategoryCollectionProxy uses CollectionProxyForwardingPolicy from AEMotionExtensionsCore.
- The host source did not import AEMotionExtensionsCore.
- Linux swift build did not reveal this because the UIKit body is excluded by #if canImport(UIKit).
- Xcode's iOS Release build compiled the UIKit body and failed with "cannot find CollectionProxyForwardingPolicy in scope".

Fix
- Add `import AEMotionExtensionsCore` to CategoryCollectionProxy.swift.
- Extend the existing index-path forwarding regression contract so it also requires the host import.

Scope
- Build-only fix.
- No runtime forwarding, effect metadata, UI, preset, or render behavior changes.
