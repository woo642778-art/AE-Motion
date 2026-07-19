# AE Motion v2.3 Shake and iPhone UI Crash Recovery Design

## Evidence

The physical-device crash report `AlightMotion-2026-07-19-202324.ips` records an `EXC_BREAKPOINT` / `SIGTRAP` on the main thread after the app had already launched and remained active. The failing stack passes through `UITableView _estimatedHeightForRowAtIndexPath:`, `UISectionRowData refreshWithSection`, and `UITableView _performBatchUpdates`. This rules out the prior dyld/framework-loading failure and makes the effect-parameter table update the first component to test.

Reported device behavior:

- `S_Pos Shake` crashes when applied.
- `S_Shake Ultra` crashes when applied.
- `S_DissolveShake` crashes when applied.
- `S_Shake` was not reported as crashing in this test.
- The iPhone AE Motion navigation item still overlaps the host render button.

## Repair strategy

### Descriptor-first isolation

Do not change the three shader algorithms during the first recovery candidate. Preserve each shader body except where a parameter type conversion requires a one-line condition change. Normalize only the parameter-table contract:

- remove empty and trailing sections
- flatten the affected descriptor controls into one stable table section
- retain parameter IDs, defaults, ranges, steps and selector choices
- require every selector default to match a declared choice
- replace Android-style boolean checkbox binding in `S_DissolveShake` with a numeric 0/1 selector and an explicit numeric shader condition
- assign explicit iOS-compatible numeric types to all spinners
- preserve effect IDs, names, categories and thumbnail paths

This candidate tests one hypothesis: the crash is caused by the descriptor/UI contract rather than the shader body. If the normalized candidate still crashes, collect a new `.ips` and investigate shader compilation or uniform binding as a separate hypothesis.

### S_Shake Ultra thumbnail

Package a valid PNG at the exact descriptor path and retain a compatibility copy for the legacy alternate filename. The package verifier must reject missing, zero-byte or non-PNG thumbnails.

### iPhone utilities control

Remove the AE Motion utilities control from `rightBarButtonItems` on iPhone. Implement a source-built floating control inside the editor view:

- 44-point minimum hit target
- constrained to the current safe-area layout frame
- draggable with a pan gesture
- normalized position persisted in `UserDefaults`
- long press resets to the default position
- reclamped after rotation, split-view or safe-area changes
- never installed over the host navigation/render controls

On iPad, retain a navigation item only when horizontal space is sufficient; otherwise use the same floating control.

## Safety boundaries

- Keep exactly one extension framework: `AEMotionExtensionsHost.framework`.
- Do not patch navigation-item selector strings in the compiled binary.
- Do not add a second framework or dylib.
- Do not hide the affected effects as the final repair.
- Do not claim visual parity until device captures confirm parameter behavior.
- Do not modify account, subscription, receipt or watermark entitlement state.

## Acceptance criteria

A recovery IPA is eligible for device testing only when:

- all affected XML files parse
- no affected descriptor contains an empty or trailing section
- selector defaults are valid
- `S_DissolveShake` has no boolean checkbox binding
- `S_Shake Ultra` thumbnail files pass PNG signature checks
- the source contains no iPhone path that appends the utilities control to `rightBarButtonItems`
- the floating control implements pan, persistence, reset and safe-area clamping
- the app contains exactly one AE Motion extension framework
- the main executable remains unchanged

Device acceptance is sequential: launch and editor first, then `S_Pos Shake`, then `S_Shake Ultra`, then `S_DissolveShake`, and finally preview/export. A failure stops the sequence and requires a fresh crash report.