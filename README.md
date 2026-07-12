# AE Motion Extensions & Scripts v1.5 Source

This package contains a cross-platform utility core and an iOS runtime host module. The host resolves `AlightMotion.EffectPickerCategoryVC`, wraps its collection view data source and delegate, inserts `Extensions & Scripts` immediately after the visible `Move & Transform` cell, and presents a native utility panel.

The hook is fail-closed. If the target class, `viewDidAppear:`, collection view, or data source cannot be resolved, installation returns without modifying the host.

## Linux validation

```bash
swift test --disable-sandbox
```

## iOS build boundary

The iOS dynamic framework requires macOS and Xcode. Build with `scripts/build-ios-framework.sh`, inject with `scripts/inject-framework.sh`, and re-sign the resulting IPA using credentials and provisioning controlled by the user. The source does not modify authentication, Keychain, subscription, or account behavior.

The first source release contains the utility engines and panel shell. Individual UIKit controls for each utility are connected during the macOS integration pass because the host layout and runtime behavior must be tested on a real iPhone.
