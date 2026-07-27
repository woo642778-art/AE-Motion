# AE Motion 2.7.1 — Home Shell Restoration

Build: 839

## User-visible changes

- Replaces the broken, overlapping Home presentation with one source-controlled AE Motion workspace shell.
- Restores readable Home cards on compact iPhones, including `3D Studio` and `Real-Time World Studio`.
- Adds a floating shell-owned navigation bar for Home, Tutorials, Create, Projects, and Templates.
- Hides the root navigation on project, template-preview, editor, and tool destinations.
- Adds a compact Create tray for New Project, Import, Camera, and Asset Library entry points.
- Removes stale AE Motion dimming overlays from Projects and Templates without replacing host data sources.
- Normalizes Projects and Templates text and surface contrast.
- Adds a native purple-violet ambient identity field, touch-position spotlight cards, interruptible springs, and subtle haptics.
- Adds Reduce Motion and Reduce Transparency fallbacks.

## Compatibility architecture

- The compiled AE Motion 2.7 framework is preserved as `AEMotionLegacy` inside the original framework bundle.
- The 2.7.1 wrapper loads the preserved framework with global symbol visibility before installing the new UI hooks.
- Existing 2.7 tools, 3D Studio, World Studio, tracking, matte, depth, color, preset, and render behavior remain in the preserved legacy binary.
- New Home controls forward to the existing 2.7 controls through known AE Motion accessibility identifiers instead of inventing private host selectors.

## Verification

- Swift core tests cover the 2.7.1 version identity and root-navigation state reducer.
- Source-contract tests cover legacy loading, visual-system requirements, Home ownership, and allowlisted runtime integration.
- Packaging tests cover in-place Mach-O install-name replacement, version metadata, wrapper and legacy presence, signing-material removal, and ZIP CRC.
- GitHub Actions builds the arm64 iOS wrapper on macOS 15 with code signing disabled.

## Known limitations

- Editing Asset Library content is not bundled in this release.
- Physical iPhone launch, touch routing, memory, thermal, CPU, GPU, and device-specific layout are not qualified until the unsigned IPA is recursively signed and installed.
- Projects and Templates retain the host application's existing data models and backend behavior.
- Rive is not bundled in 2.7.1. The release uses UIKit and Core Animation only.
