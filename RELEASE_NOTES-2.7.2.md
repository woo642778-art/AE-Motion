# AE Motion 2.7.2 — Recovery Candidate

Build: 840

## Recovery objective

This candidate corrects the rejected 2.7.1 integration architecture. It starts from the user-supplied `AE Motion 2.7(2).ipa` and preserves the complete existing extension set while loading the source-controlled Home Shell through a separate, recursively signable framework bundle.

## Preserved and reapplied behavior

- Existing AE Motion Home, effects and extension framework remain at their original app load path.
- The previously verified Home root-surface visibility guard is reproduced byte-for-byte.
- Telegram promotion strings and metadata point to `https://t.me/aemotionios`.
- Settings retains the TikTok target `https://www.tiktok.com/@ss09102?`.
- Existing Asset Library, 3D Studio, World Studio, Cutout, Depth, Tracking, Matte and preset markers remain in the original extension binary.

## New integration architecture

- Adds `AEMotionUI272.framework` as its own framework bundle.
- Adds one explicit host `LC_LOAD_DYLIB` command for `@rpath/AEMotionUI272.framework/AEMotionUI272`.
- The existing `AEMotionExtensionsHost.framework` load command stays earlier in load order.
- No `AEMotionLegacy` sibling executable is created.
- No `dlopen` wrapper is used.
- The host executable's code and data sections remain byte-identical; only Mach-O header counters and previously unused load-command padding change.

## Home Shell

- Adaptive Workspace Home layout.
- Floating Home, Tutorials, Create, Projects and Templates navigation.
- Purple ambient field and touch-position spotlight cards.
- Interruptible native spring animations.
- Reduce Motion and Reduce Transparency fallbacks.
- Existing host actions remain connected through known AE Motion accessibility identifiers.

## Qualification status

This is an unsigned physical-device recovery candidate, not a final release.

Automated validation covers:

- Swift tests and source contracts,
- generic arm64 iOS framework compilation,
- framework install name and metadata,
- exact baseline and known-fix hashes,
- Mach-O load-command insertion,
- unchanged executable sections,
- ZIP CRC and signing-material removal.

Physical iPhone validation is still required for:

- launch and signing,
- existing extension presence,
- Home Shell appearance and routing,
- 3D and World Studio entry,
- Cutout, Depth, Tracking and Matte entry,
- background/foreground behavior,
- memory, CPU, GPU and thermal behavior.

## Deferred phases

The duplicate runtime launch overlay, Google Drive asset catalog and timeline insertion, full 3D timeline handoff and performance profiling follow only after this recovery candidate preserves both the old and new functionality on a real device.
