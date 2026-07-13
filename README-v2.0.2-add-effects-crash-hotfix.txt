AE Motion Extensions v2.0.2 — Add Effects crash hotfix

Device evidence
- Alight Motion 6.2.42, iPad14,3, iOS 26.5
- EXC_BREAKPOINT / SIGTRAP on the main thread
- Crash occurred during UICollectionView will-display notification while the AE Motion effect-picker resize path forced layout
- The host frame was using IndexPath.subscript immediately before the trap

Root cause
- CategoryCollectionProxy inserted one synthetic Extensions & Scripts item.
- Its generic Objective-C forwarding advertised the original delegate's optional index-path callbacks.
- UIKit delivered the synthetic index path to willDisplayCell.
- The callback was forwarded unchanged to Alight Motion's original delegate, which indexed its original category model and trapped because that synthetic item does not exist there.

Fix
- Unknown Objective-C callbacks containing IndexPath are no longer generically forwarded.
- Common selection, highlight, will-display and end-display callbacks are intercepted explicitly.
- Original rows are translated back to original index paths.
- Synthetic-row callbacks are handled locally or suppressed.
- Callbacks without index paths continue to use the original forwarding behavior.

Scope
- Add Effects collection proxy only.
- No changes to effect metadata, theme, project toolbar, presets or rendering.
