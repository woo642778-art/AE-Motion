# Home Shell UI Restoration Design

## Status and source-parity gate

This design covers the first UI-recovery phase approved by the user: Home, Projects, and Templates only. Asset Library population, render-engine work, AI models, 3D engine expansion, World Studio expansion, and unrelated settings changes are excluded.

The current `main` branch contains the v2.0.2 extension-host architecture, including `AEMotionTheme`, Effect Picker integration, and ProjectEditVC tool placement. It does not contain the v2.5-v2.7 Home shell implementation shown in the supplied device screenshots. The unsigned v2.7 IPA and framework are compiled artifacts, not an acceptable substitute for the missing Swift source.

No source-level UI implementation may begin until the exact v2.7 Home shell source is committed to this repository or a verified source commit/branch is restored. The implementation must not invent controller names, file paths, runtime selectors, data models, or layout ownership based on binary strings or screenshots.

## Problem statement

The supplied broken-state screenshots show four distinct classes of defects:

1. The custom AE Motion workspace is composed under the stock Alight Motion header instead of owning one coherent screen surface.
2. Home cards use unstable widths and compression resistance, causing labels such as `3D Studio` to wrap into narrow vertical fragments and descriptions to truncate prematurely.
3. Projects and Templates appear under a persistent dark or dim layer, reducing text, image, and control contrast across the entire content area.
4. The custom bottom navigation is visually and structurally inconsistent across screens and may be attached above the active content controller rather than owned by a single shell controller.

The normal reference establishes the target: one full-screen AE Motion shell, compact top branding, consistent dark surfaces, one stable bottom navigation bar, readable cards, and no inherited stock header inside the custom workspace.

## Scope

### Included

- Home shell root ownership and safe-area layout.
- Home workspace content hierarchy and card sizing.
- Projects screen surface, header, tabs, rows, and content contrast.
- Templates screen surface, category strip, filters, cards, loading states, and content contrast.
- Shared bottom navigation for Home, Tutorial, Create, Project Editor/Projects, and Templates.
- Shared dark visual tokens and reusable card/header components.
- Removal of accidental persistent dimming, overlay, or presentation layers.
- Layout validation on compact and regular iPhone widths.
- Dynamic Type and VoiceOver behavior for the affected screens.

### Excluded

- Editing Asset Library content ingestion.
- New project/template backend behavior.
- Changes to Alight Motion private project storage.
- 3D or World Studio feature expansion.
- Effect rendering, tracking, matte, depth, or export changes.
- Rebranding unrelated host screens.
- Binary-only patching as the final source of truth.

## Architecture

### 1. Single shell owner

The restored UI must have one controller responsible for the custom application shell. That owner contains:

- one content container,
- one bottom navigation component,
- one selected-tab state,
- one route-to-content mapping,
- and one appearance policy.

Individual Home, Projects, and Templates controllers must render only their content. They must not independently install, retain, or reattach the global bottom navigation. Navigating from these root tabs into a project, template detail, editor, modal tool, or imported host controller must hide the custom shell navigation unless the destination is explicitly a root-tab destination.

### 2. Host chrome boundary

The custom Home shell must not be embedded beneath the stock Alight Motion Home header. The integration layer must select exactly one presentation mode:

- full custom shell replacing the host Home content and chrome for the affected route, or
- stock host screen with no custom full-page shell.

It must never display both simultaneously. The integration remains fail-closed: if the exact host boundary cannot be verified, leave the stock host UI unchanged rather than partially overlaying AE Motion content.

### 3. Shared visual system

Extend the existing theme architecture instead of creating per-screen constants. The restored shell uses semantic tokens for:

- canvas background,
- primary and secondary surfaces,
- elevated surfaces,
- primary, secondary, and disabled text,
- accent purple,
- separators and strokes,
- card radius,
- horizontal margins,
- section spacing,
- bottom-navigation height,
- and minimum touch targets.

The current system-blue accent in `AEMotionTheme` must not be changed globally unless repository evidence confirms all existing extension screens should adopt the purple product accent. The shell may use a dedicated product-surface token layered on the shared theme to avoid regressing Effect Picker and utility screens.

### 4. Reusable components

The implementation should reuse or introduce narrowly scoped components only after confirming equivalents do not already exist in the restored v2.7 source:

- product header,
- section header,
- recent-project card,
- action tile,
- destination card,
- quick-tool tile,
- project row,
- template card,
- loading state,
- empty/error state,
- and shell bottom navigation.

Every component must have an intrinsic or constrained layout that remains readable at compact widths. Fixed text-column widths that produce fragmented words are prohibited.

## Screen design

### Home

The Home screen follows the compact normal reference hierarchy:

1. AE Motion product branding.
2. `Workspace` title and subtitle.
3. Recent project card.
4. `Start` section with New Project, Import, Tutorials, and Templates actions.
5. Full-width 3D Studio and Real-Time World Studio destination cards.
6. `Quick tools` horizontal or adaptive grid.

The oversized Live Composition hero from the broken build is not part of the first restored layout. It may return later only as an optional, independently validated module that does not displace core actions or break compact layouts.

### Projects

The Projects screen must use the same shell surface and readable contrast as Home. The stock or custom project data remains unchanged. The UI restoration is limited to:

- removing any unintended global dim state,
- preserving the Projects/Your Templates/Elements selector,
- ensuring row text and metadata meet contrast requirements,
- keeping thumbnails and overflow actions interactive,
- and keeping the bottom navigation owned by the shell.

### Templates

The Templates screen must preserve category, filter, save, loading, and navigation behavior while removing unintended global dimming. Loading indicators may dim only their individual card media area, not the entire screen. Text overlays must use explicit contrast surfaces or gradients and remain readable over thumbnails.

## Overlay and presentation policy

A dimming view may exist only while a corresponding modal, menu, sheet, or blocking operation is actively presented. Its lifecycle must be tied to that presentation and removed on cancellation, completion, dismissal, tab change, background/foreground transition, and controller deallocation.

The implementation must not search all window subviews and delete arbitrary dark views. It must identify the exact overlay owner and fix lifecycle state at the source.

## State and navigation rules

- Root-tab selection is the only source of truth for the highlighted bottom-navigation item.
- Re-selecting the active root tab may scroll to top but must not create another controller instance.
- Opening a project or template detail hides the root bottom navigation.
- Returning to a root tab restores its previous scroll and filter state.
- Presenting a modal does not mutate root-tab selection.
- Background/foreground transitions do not duplicate the shell, header, or bottom navigation.
- Safe-area changes and rotation trigger layout recalculation without installing new views.

## Accessibility and adaptive layout

- Minimum interactive target: 44 by 44 points.
- Labels use Dynamic Type-compatible fonts.
- Content supports compact iPhone widths without word fragmentation.
- Cards use multiline labels only at natural word boundaries.
- VoiceOver order follows visual order.
- Decorative images are hidden from accessibility.
- Selected tab state is announced.
- Reduce Transparency receives an opaque bottom-navigation fallback.
- Reduce Motion disables nonessential shell transitions.

## Testing strategy

Implementation must follow test-first development after source parity is restored.

### Source-contract tests

- Exactly one shell owner installs the bottom navigation.
- Home, Projects, and Templates content controllers do not install global navigation directly.
- The host-chrome integration is allowlisted and fail-closed.
- Dimming overlays have explicit presentation owners and cleanup paths.
- The affected controllers use shared theme/component APIs rather than duplicated hard-coded styles.

### UIKit and snapshot tests

Test at minimum:

- iPhone SE-class compact width,
- standard 6.1-inch iPhone width,
- large iPhone width,
- default and accessibility text sizes,
- dark appearance,
- Reduce Transparency,
- Home, Projects, and Templates root states,
- Templates loading and error states,
- project/template detail navigation with the root tab bar hidden,
- and return-to-root state restoration.

### Runtime regression tests

- Open and close each root tab 20 times with no duplicate shell views.
- Open project and template destinations and verify no root bottom navigation remains visible.
- Present and dismiss menus/sheets and verify no persistent dim layer.
- Background and foreground the app from each root tab.
- Verify existing Effect Picker, ProjectEditVC tool menu, Preset Studio, and utility controllers are unaffected.

## Completion criteria

This UI phase is complete only when all of the following are true:

- The repository contains the exact source corresponding to the active v2.7 build lineage.
- Home no longer displays stock Alight Motion chrome together with the custom AE Motion shell.
- `3D Studio` and all destination-card text remain readable without fragmented wrapping on compact iPhones.
- Projects and Templates have no unexplained full-screen dim layer.
- One shell-owned bottom navigation appears only on root-tab screens.
- Navigating to project, template, editor, or tool destinations hides the root navigation.
- Snapshot, source-contract, Swift tests, iOS framework build, and simulator interaction tests pass.
- Unverified physical-device behavior is reported as unverified rather than inferred.

## Known blocker

The v2.7 Home shell Swift source is not present on the current `main` branch. The next implementation action is therefore source restoration or source import, not UI code invention. Once the exact source is available in GitHub, the implementation plan will name the verified files, types, methods, tests, and commands.
