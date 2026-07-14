# Implementation Status

## Complete in this source package

- Stable `Extensions & Scripts` category injection after Move/Transform.
- v2.0 XML preset platform and v2.0.1 Preset Studio navigation/application stabilization.
- v2.0.2 semantic `AEMotionTheme` shared by extension forms, tables, text views and empty states.
- Dynamic Extensions hub sections for Recent, Favorites, Editing Shortcuts, Scripts, Presets, Resources and Diagnostics.
- Explicit `ToolPlacementRegistry` so contextual editing tools do not default to the Extensions hub.
- Safe allowlisted ProjectEditVC toolbar menu with Speed Remap, Person Cutout, Depth Map, Dead Frame Cleaner and Preset Studio entry points.
- Solid and empty-state backgrounds for Effect Picker collections, including collapsed recommendation-strip space.
- Centralized `ToolControllerFactory` for consistent tool presentation.
- Existing Move/Transform, Distortion/Warp and BCC metadata restoration.
- Existing render cancellation, duplicate prevention, memory limits and temporary-file cleanup.

## Automated verification

- Swift core tests.
- Effect metadata normalization tests.
- Effect integrity parser, audit and quarantine tests.
- Swift 6 LocalizedError isolation regression test.
- Native UI source-contract test.
- Xcode arm64 iOS Release framework build.

## v2.0.3

- [x] Approved effect-integrity design committed.
- [x] Stable Swift effect-integrity models and visibility policy.
- [x] XML/GLSL descriptor parser and static integrity report.
- [x] Pre-sign unsafe-effect quarantine tooling.
- [x] Packaged-report loader and Effect Integrity diagnostics UI.
- [x] IPA packaging contract with `AE motion` name and supplied icon support.
- [x] GitHub Actions Xcode arm64 iOS Release build.
- [x] Beta 16 packaged IPA static verification with the new framework artifact.
- [ ] iPhone/iPad device verification and crash-log review.
- [ ] v2.0.3b verified clean-room effect pack.

## Requires iPhone/iPad validation

- Verify ProjectEditVC runtime class resolution against the installed Alight Motion build.
- Verify the contextual toolbar item or compact overlay does not overlap host controls.
- Verify all Effect Picker backgrounds in category, search, empty and overscroll states.
- Verify Effect Integrity summary/detail states with missing, malformed and valid reports.
- Verify iPhone and iPad layouts, rotation, Dynamic Type and VoiceOver.
- Recursively sign and test the unsigned IPA.

The source does not write to Alight Motion's private timeline or project database.
