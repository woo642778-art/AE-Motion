# Implementation Status

## Complete in this source package

- Cross-platform category insertion model with `Extensions & Scripts` after `Move & Transform`.
- Nine independent utility engines and stable tool registry.
- Fail-closed runtime resolver for `AlightMotion.EffectPickerCategoryVC`.
- Collection-view proxy design that adds one synthetic category and forwards original data-source/delegate behavior.
- Native panel shell with Extensions, Scripts, Presets, Utilities, and Favorites sections.
- Constructor bridge and macOS build/injection scripts.
- Linux build and 8 XCTest cases with 0 failures.

## Requires macOS/iPhone validation

- Compile the arm64 iOS dynamic framework with Xcode.
- Verify Swift runtime class resolution against the exact installed Alight Motion build.
- Verify the collection-view proxy's insertion index and cell sizing on-device.
- Inject the framework, re-sign the IPA, and test launch/account/effect-browser flows.
- Connect full UIKit controls for each utility after panel presentation is confirmed.

The source intentionally does not hook project/timeline internals yet. That work begins only after the panel is stable and the relevant host object boundaries are identified on-device.
