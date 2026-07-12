AE Motion Extensions v2.0.0 — Preset Platform implementation

Implemented
- Public XML preset schema 1.0 with typed parameters, curves, macros, dependencies, compatibility rules, preview images, and editable-template metadata.
- XML import/export and schema migration.
- Atomic Builtins/User/Quarantine storage.
- Create, edit, duplicate, rename, delete, search, sort, favorites, collections, recent usage, and usage counts.
- Easy macro controls with stable Advanced parameter synchronization.
- Runtime validation and dependency reporting.
- Functional preset application for Speed Remap, Easing Curve, Camera Shake, and Color Palette.
- Save-current-preset actions in those tools.
- DaFont and Keyfla.me resource hub with license warnings.
- Add Effects category repair for native `transform` and `distort` keys.
- BCC/BBC/BorisFX/Continuum aliases retained.
- Effect-category integrity diagnostics.

Packaging requirement
- Build the new AEMotionExtensionsHost.framework with GitHub Actions.
- Package the final IPA from AE-Motion-v1.9.1-beta10-unsigned.ipa, not Beta 11.
- After embedding the framework, run:
  python3 scripts/normalize-effect-search-metadata.py --require-native-groups <Payload/AlightMotion.app>
- Expected source category preservation after normalization: transform > 0 and distort > 0.

Not implemented in v2.0
- Direct writes to Alight Motion's private timeline or project database.
- Online preset marketplace or payments.
- Native third-party plugin execution.
- Universal keyframes, Null/Parenting, Pre-compose, node color, AI media engine, or 2.5D; these remain later roadmap items.

Validation completed in the Linux environment
- Swift source parse passed.
- Swift package build passed.
- 31 Swift tests passed with zero failures.
- 4 Python metadata tests passed.
- Beta 10 category packaging check passed: transform 39, distort 109.
- Beta 11 category packaging check correctly failed because transform metadata was already lost.

Remaining verification
- GitHub Actions Xcode/iOS framework build.
- Physical-device UI and private UIKit hook tests.
