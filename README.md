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

### v1.5.3 category height fix

The injected category increases the stock category count by one. `EffectPickerMainVC`
uses a fixed `categoriesCollectionViewHeightConst`, so v1.5.2 could clip Repeat and
later categories. v1.5.3 recalculates that constraint from the collection layout's
content size after insertion, preserving every stock category.

### v1.5.4 safe runtime outlet lookup

v1.5.3 queried `categoriesCollectionViewHeightConst` with KVC. On app builds
without that exact Objective-C key, UIKit raises `NSUnknownKeyException` while
opening Add Effects. v1.5.4 resolves the getter/backing ivar through the Objective-C
runtime and falls back to scrolling when the constraint is unavailable.

### v1.5.5 shifted delegate index-path fix

The device crash report showed `UICollectionView willDisplay` reaching Alight
Motion with the synthetic collection index path. v1.5.5 translates stock item
paths back to the original model for display, selection, highlight, deselection,
and focus callbacks. The synthetic Extensions cell is never forwarded. Unknown
optional/private item-index-path callbacks are not advertised to UIKit, avoiding
untranslated shifted paths.

## Normalize custom effect search metadata

Before repacking an IPA, normalize the installed effect XML files so custom BCC effects use an indexed category and can be found through `BCC`, the common `BBC` typo, `Boris`, `BorisFX`, or `Continuum`:

```bash
python3 scripts/normalize-effect-search-metadata.py \
  /path/to/Payload/AlightMotion.app
```

The normalizer edits only the opening `<effect>` attributes and preserves the effect body, parameters, shaders, and resource references.
