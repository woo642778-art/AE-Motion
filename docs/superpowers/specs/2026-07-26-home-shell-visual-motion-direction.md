# AE Motion 2.7.1 Home Shell Visual and Motion Direction

## Goal

Restore Home, Projects, and Templates as a coherent native iOS product surface, then raise the visual quality above the broken v2.5-v2.7 shell without turning the app into a web-demo gallery. The result must feel distinctive at first launch, remain readable on compact iPhones, and preserve editor performance.

## Reference sources

The following sites are design and interaction references, not a blanket authorization to copy their source code:

- KokonutUI: https://kokonutui.com/
- React Bits Showcase: https://reactbits.dev/showcase
- Bklit UI: https://bklit.com/
- Limora: https://limora.ai/
- Anime.js: https://animejs.com/
- Motion: https://motion.dev/
- Rive: https://rive.app/
- Magic UI: https://magicui.design/

Every borrowed pattern must be translated into UIKit, Core Animation, Metal, or the official Rive Apple runtime. React, Tailwind, DOM, cursor, hover, and browser-specific code must not be embedded into the native shell.

## Selected design patterns

### 1. Morphing shell navigation

Reference direction: KokonutUI Smooth Tab and Toolbar, React Bits Dock, Magic UI Dock.

Native implementation intent:

- One shell-owned floating bottom bar.
- A single selected-tab capsule moves between destinations using interruptible spring animation.
- The central Create control expands into a compact action tray for New Project, Import, Camera, and Asset Library entry points.
- Selection changes use subtle haptics and preserve the current root-controller instance.
- Detail, editor, template-preview, and modal-tool routes hide the root bar.
- Reduce Motion replaces morphing with a short crossfade.

The bar must never be independently installed by Home, Projects, or Templates.

### 2. Spotlight destination cards

Reference direction: React Bits Spotlight Card, KokonutUI Mouse Effect Card, Magic UI Magic Card and Shine Border.

Native implementation intent:

- 3D Studio and Real-Time World Studio use full-width destination cards.
- A touch-position radial highlight follows the finger only while interacting.
- Pressing applies a small scale and depth response, then returns through an interruptible spring.
- A restrained purple edge light identifies the active card.
- No permanent particle field, cursor simulation, or continuous GPU-heavy shader is allowed.

The text column uses content-driven constraints so `3D Studio` cannot fragment vertically on compact widths.

### 3. Recent project stage

Reference direction: KokonutUI Card Stack, React Bits Card Swap, Magic UI Animated List.

Native implementation intent:

- The latest project remains the primary action.
- Up to two older project thumbnails may appear as offset background layers when real project data exists.
- Press-and-hold reveals project metadata and secondary actions without replacing the main tap behavior.
- Thumbnail motion is limited to the initial reveal and direct interaction.
- The card falls back to one stable surface when only one project exists.

No fake projects, generated statistics, or placeholder data may ship.

### 4. Ambient AE Motion identity

Reference direction: React Bits Iridescence and Aurora, Magic UI Light Rays and Noise Texture, Limora's persistent brand-system approach.

Native implementation intent:

- The shell uses a near-black canvas with a restrained purple-violet ambient field behind the upper Home region.
- The effect is generated from native gradients or a small Metal shader after profiling.
- The ambient layer pauses when obscured, backgrounded, or outside the visible Home region.
- Reduce Transparency receives an opaque gradient fallback.
- The effect must not reduce text contrast or appear beneath Projects and Templates list content.

Limora is used only as a reference for maintaining one consistent brand language across thumbnails, empty states, loading surfaces, and promotional media. No Limora product assets or proprietary output are bundled without explicit rights.

### 5. Rive micro-interactions

Reference direction: Rive state machines, Apple runtime, data binding, and event-driven playback.

Permitted first-release uses:

- AE Motion mark or launch-to-Home transition.
- Empty project and empty template states.
- Successful import confirmation.
- Compact progress or status illustration where a static SF Symbol is insufficient.

Rive must not own the global navigation, project list, template grid, or editor viewport. The shell remains functional when a Rive asset fails to load. Rive is added only through Swift Package Manager after dependency, binary-size, license, and runtime-performance review.

### 6. Motion language

Reference direction: Anime.js timelines and Motion springs, gestures, layout transitions, and interruptible animation.

Native translation:

- Use `UIViewPropertyAnimator`, `UISpringTimingParameters`, `CASpringAnimation`, and matched snapshot transitions where appropriate.
- All interactive animations must be interruptible and reversible.
- Scroll-driven effects must derive from actual scroll state and must not allocate a new animator every frame.
- Initial content reveals may use a restrained stagger. Re-entering a tab must not replay the entire entrance sequence.
- Loading indicators are scoped to the item that is loading, never a full-screen unexplained dim layer.

Recommended motion tiers:

- Micro feedback: 120-180 ms.
- Selection and card response: 180-280 ms.
- Root content transition: 240-420 ms.
- Continuous ambient motion: optional, low amplitude, pausable, and excluded from Reduce Motion.

These are design targets. Final values must be tuned using Simulator and physical-device evidence.

### 7. Project and template information visualization

Reference direction: Bklit UI chart hierarchy, grid discipline, tooltips, and compact data presentation.

Native implementation intent:

- Bklit patterns are reserved for meaningful editor or diagnostics data such as render progress, storage distribution, audio levels, frame-time history, and world-performance metrics.
- Home must not become a dashboard of decorative charts.
- Projects may show only verified metadata already available from the host or project model.
- Chart code is implemented natively and receives accessibility summaries.

Bklit source is not copied unless its exact component license is verified and documented.

## Screen-specific application

### Home

- Rive or native AE mark transition on first eligible launch.
- Compact Workspace header over a restrained ambient purple field.
- Recent project stage with direct Continue Editing action.
- Four Start tiles with a single initial stagger.
- Spotlight response on 3D Studio and Real-Time World Studio cards.
- Quick Tools presented as a stable adaptive row, not an endlessly animated carousel.
- Floating shell navigation with morphing selected state and expandable Create action.

### Projects

- No ambient hero or decorative shader behind the list.
- Clear project metadata and thumbnails on opaque surfaces.
- Row insertion, deletion, and selection use short native transitions.
- Any loading state affects only the corresponding row or thumbnail.
- Bottom navigation is visible only at the root Projects destination.

### Templates

- Category and filter changes use matched selection movement and content crossfade.
- Template cards may use a restrained shine or border response on touch.
- Skeleton or shimmer is constrained to each loading card.
- No full-screen dim layer remains after loading, dismissal, tab change, or background transition.
- Template detail hides root navigation and restores filter and scroll state on return.

## Surprise moments

The release may contain three deliberate signature moments, provided each passes performance and accessibility gates:

1. The AE mark resolves from a compact Rive or native state-machine animation into the Workspace header.
2. The central Create button expands into a four-action tray with synchronized haptics and an interruptible morph.
3. 3D Studio and Real-Time World Studio cards respond to touch with a local spotlight and subtle depth shift.

No additional spectacle should be added to v2.7.1. Restraint is part of the design.

## Rejected patterns

- Mouse cursors, hover-only interactions, cursor trails, or browser pointer effects.
- Continuous text scrambling on navigation labels.
- Full-screen particles behind scrolling lists.
- Auto-playing card rotations that move without user input.
- Large WebView surfaces used to host React components.
- Unlicensed React Bits Pro source or assets.
- Copying Limora branding, illustrations, or generated assets.
- Decorative charts with invented data.
- Animations that block navigation or delay opening an editor.

## Licensing and provenance policy

- Motion, Anime.js, Magic UI, and the Rive runtime have public open-source distributions, but any copied code or bundled dependency still requires its license text and provenance to be recorded in the repository.
- React Bits free components use a separate license with additional terms. React Bits Pro requires a purchased license and must not be copied without one.
- KokonutUI and Bklit components remain concept-only until the exact component license is verified.
- Limora is a visual-product reference only.
- The implementation plan must list every added dependency, license, version, binary-size effect, and removal strategy.

## Performance gates

- Home scrolling must remain responsive while ambient and card effects are enabled.
- Off-screen continuous animation must pause.
- Only one ambient animated surface may be active in the root shell at a time.
- Project and template lists must not create per-frame heap allocations from animation code.
- Rive and Metal usage must be profiled independently before both are enabled together.
- Reduce Motion and Reduce Transparency must produce complete, intentional alternatives.
- Any effect causing visible frame drops, excessive memory growth, thermal escalation, or navigation delay is removed rather than hidden behind a quality claim.

## Versioning

The first verified implementation of this direction is AE Motion `2.7.1`. The product version changes only after the UI source exists in the repository and the implementation passes source-contract tests, Swift tests, the iOS framework build, snapshot checks, and simulator interaction tests. Build numbers increase for every build attempt according to the repository's centralized version source once it is restored or introduced.

## Completion criteria

- The shell is visually coherent without stock and custom chrome overlap.
- Home, Projects, and Templates remain readable at compact widths and accessibility text sizes.
- Root navigation is owned once and hidden on non-root destinations.
- No unexplained persistent dim layer exists.
- The selected signature interactions work with Reduce Motion fallbacks.
- Every third-party dependency and adapted pattern has a documented license and provenance decision.
- UI performance is measured rather than inferred.
- The final report distinguishes Simulator, physical-device, memory, GPU, and thermal verification status.