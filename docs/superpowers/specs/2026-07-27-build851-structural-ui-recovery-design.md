# AE Motion 2.7.2 Build 851 Structural UI Recovery Design

## Status

Approved approach: **B — replace the Build 846–850 overlay integration with a structurally owned controller hierarchy and explicit routing.**

Target branch: `fix/2.7.2-recovery`

Target release:

- Marketing version: `2.7.2`
- Candidate build: `851`
- Output status: unsigned physical-device candidate

Builds 846–850 are rejected as release candidates. Their visual components may be reused selectively, but their runtime shell attachment, repeated refresh, modal routing, and action-forwarding architecture must not be retained.

## Device evidence

Physical-device screenshots from Build 850 show the following regressions:

1. The official Telegram card is compressed into a narrow vertical column and overlaps the Create tray and bottom navigation.
2. The legacy Blatant promotion is visible again.
3. The AE Motion UI appears roughly one second after the host UI, producing visible replacement and inconsistent state.
4. The Create tray cannot always be dismissed.
5. Settings has no reliable Back or Close path.
6. Account presentation enters and then dismisses unexpectedly.
7. Home actions do not reliably open New Project, Import, Camera, Asset Library, 3D Studio, or Real-Time World Studio.
8. Projects and Templates can remain covered by Home-owned views or dimming surfaces.
9. Header metadata still displays `Build 846` in later packages.
10. Bottom navigation, custom header, host tab state, and modal state are controlled by separate asynchronous refresh loops.

These are architectural failures, not isolated Auto Layout defects.

## Root cause

Builds 846–850 attach one full-window AE Motion `UIView` over the existing application window and repeatedly rediscover the current host controller.

The current implementation has five incompatible ownership models:

- the host `UITabBarController` owns root navigation state;
- the AE Motion Shell separately owns selected-tab state;
- `AEMotionGlobalShellCoordinator` repeatedly infers the active controller;
- `AEMotionHostSurfaceAdapter` hides and restores host subviews asynchronously;
- modal and tool actions are forwarded to hidden legacy controls using `sendActions(for: .touchUpInside)`.

This produces delayed installation, duplicate state transitions, touch interception, modal dismissal races, stale header metadata, and routes that report success before a destination actually opens.

The Blatant regression was introduced when the Build 850 package restored the verified strings-only `AlightMotion.dylib` in order to avoid the earlier initializer and callback patches. That rollback also restored the legacy promotion creation path. String replacement alone cannot prevent the promotion window from being created.

## Design decision

Build 851 will use one root container, one shell owner, one route state, and one explicit presentation coordinator.

The implementation must not attempt to repair Build 850 by adding another timer, sanitizer burst, global subview search, hidden-button forwarding layer, or window-level overlay.

## Architecture

### 1. Root installation boundary

AE Motion installation occurs once, after the real application window and host root controller are available.

The installer must:

1. identify the single foreground normal-level application window;
2. verify that its root controller contains the expected host `UITabBarController`;
3. verify that no modal, splash, loading, account, settings, editor, export, or promotion controller is currently presented;
4. replace the window root exactly once with `AEMotionRootContainerViewController`;
5. embed the original host root controller as a retained child;
6. embed one `AEMotionShellViewController` as a retained child above the host only where the route policy requires it;
7. store an installation marker using associated state or a retained coordinator so installation is idempotent.

There must be no continuous 120-attempt refresh burst and no delayed full-window overlay attachment.

### 2. Root container ownership

`AEMotionRootContainerViewController` is the permanent owner of:

- the original host root controller;
- the AE Motion root shell controller;
- status-bar and orientation forwarding;
- root shell visibility;
- modal presentation routing;
- transition coordination between host and AE Motion destinations.

The root container must use proper child-controller containment:

- `addChild`
- constrained child views
- `didMove(toParent:)`
- paired removal where needed

The shell must never be inserted directly into a `UIWindow` as an unmanaged view.

### 3. Single route state

Introduce one route model with explicit states:

```text
root.home
root.tutorials
root.projects
root.templates
modal.createTray
modal.settings
modal.account
modal.channel
nonRoot.projectEditor
nonRoot.templatePreview
nonRoot.threeDStudio
nonRoot.worldStudio
nonRoot.tool
nonRoot.export
```

The route state is the only source of truth for:

- selected bottom-navigation item;
- shell header visibility;
- bottom-navigation visibility;
- create-tray visibility;
- host-root visibility;
- AE Motion Home or Tutorials visibility;
- modal eligibility;
- Back or Close behavior.

No view controller may independently infer or overwrite root navigation state.

### 4. Root-tab composition

#### Home

Home is fully source-controlled by AE Motion.

The host Home view is not shown underneath the AE Motion Home surface. Existing host controls may be resolved once during installation for compatibility, but Home actions must not depend on sending events to hidden controls.

#### Tutorials

Tutorials is fully source-controlled by AE Motion.

#### Projects

Projects uses the actual host Projects controller inside the host tab controller. AE Motion provides only the shared header and bottom navigation around it. Project data source, collection or table ownership, selection, deletion, templates, elements, and project-opening behavior remain host-owned.

#### Templates

Templates uses the actual host Templates controller. AE Motion provides only shared root chrome. Template data, category state, filters, loading, save actions, and template-preview behavior remain host-owned.

### 5. Explicit action routing

Replace optimistic hidden-control forwarding with an explicit action router.

Each action must return a result:

```text
opened(destination)
requiresOpenProject
unavailable(reason)
failed(reason)
```

The shell state changes to a non-root destination only after the router confirms that the destination was presented or pushed.

Required mappings:

- New Project → verified host project-creation API or verified visible host control
- Import → verified host import API or verified visible host control
- Camera → verified camera presentation path
- Asset Library → verified AE Motion Asset Library controller
- Continue Editing → verified latest-project or active-project route
- 3D Studio → production `ThreeDStudioProjectBrowserViewController`
- Real-Time World Studio → production `WorldStudioProjectBrowserViewController`
- Quick Tools → active Project Editor only; otherwise show an explicit `Open a project first` result

Fallback control forwarding is permitted only when all of the following hold:

- the target control is visible in the active host hierarchy;
- the target control is enabled and attached to the current window;
- the route can verify that a destination appeared;
- failure leaves the shell in its previous state.

Hidden or detached controls must never be treated as successful routes.

### 6. Settings and Account

Settings and Account must be presented through a dedicated `UINavigationController` with an explicit leading Back or Close button.

Presentation requirements:

- one presentation at a time;
- no coordinator refresh while presented;
- dismissal returns to the exact prior root tab;
- Account may not disappear unless the user closes it, login flow completes, or the host explicitly dismisses it;
- interactive dismissal must update route state through `UIAdaptivePresentationControllerDelegate`;
- presentation failure must leave the root shell interactive.

### 7. Create tray behavior

The central Create button is a toggle.

The tray closes when:

- the Create button is pressed again;
- the user taps outside the tray;
- a tray action is selected;
- another root tab is selected;
- a modal or non-root destination opens;
- the application enters the background;
- the root shell is hidden.

The background dismiss region must not block bottom navigation or tray buttons. The tray must be removed from hit testing when hidden.

### 8. Telegram promotion

Build 851 uses one source-controlled official-channel presentation only.

Official URL:

`https://t.me/aemotionios`

The source-controlled card must:

- present after the root container is stable;
- appear once per release key;
- have a readable width on compact iPhones;
- support Dynamic Type and vertical scrolling;
- remain entirely above the bottom safe area;
- provide `Join Channel` and `Continue to AE Motion` actions;
- open the official URL directly;
- never coexist with the Create tray;
- never present while another modal is active.

Recommended layout constraints:

- safe-area horizontal inset: minimum 20 points;
- card width: `min(430, safeAreaWidth - 40)`;
- vertical content wrapped in a scroll view;
- maximum height constrained to safe-area height minus 40 points;
- no fixed narrow intrinsic width derived from label content.

### 9. Legacy Blatant suppression

Build 851 must not restore the Build 850 strings-only behavior as the sole suppression mechanism.

Suppression is split into two independently verified layers:

#### Packaging layer

- remove or neutralize all UTF-8 and UTF-16 Blatant branding strings;
- replace legacy Telegram URLs with `https://t.me/aemotionios` where byte-safe;
- verify zero app-wide occurrences of `Blatant`, `Cracked By`, and `t.me/blatants`;
- preserve unrelated initialization and compatibility behavior.

#### Runtime structural layer

For a bounded startup interval, identify only promotion windows or controllers that match the verified legacy structure:

- non-normal window level or alert-level presentation;
- promotion-specific class or controller signature;
- legacy promotion labels or button arrangement;
- not the main application root window;
- not Settings, Account, editor, export, system alert, or AE Motion official-channel view.

A matching legacy promotion may be dismissed or hidden. Generic searches for dark views or arbitrary windows are prohibited.

The suppression observer ends after the root shell is established and the bounded startup interval expires. It must not run indefinitely.

### 10. Build metadata

`AEMotionRelease.buildNumber` is the single source of truth for visible and packaged build identity.

The header must render:

```text
<Section> · Build 851
```

No source file may contain stale user-visible literals such as `Build 846`, `Build 848`, `Build 849`, or `Build 850`.

Framework Info.plist, app Info.plist, release manifest, verification report, artifact name, and visible header must agree on Build 851.

## Touch and presentation policy

The shell must own only its visible regions.

- Home and Tutorials content are interactive because they are source-controlled shell content.
- Projects and Templates center content must remain host-owned and receive touches directly.
- Header, bottom navigation, Create tray, and source-controlled modal surfaces are shell-owned.
- A transparent full-screen shell view must not intercept touches outside active shell regions.
- Hidden views must have `isUserInteractionEnabled = false` and be excluded from hit testing.

## Layout requirements

The affected UI must be tested at minimum at:

- 320-point compact width;
- 375-point standard width;
- 390/393-point modern iPhone width;
- 430-point large iPhone width;
- default Dynamic Type;
- accessibility text sizes;
- Reduce Motion;
- Reduce Transparency.

No title, button, or card may fragment into one- or two-character vertical lines. Buttons must preserve at least 44 by 44 point targets.

## Error handling

Routing and presentation failures must be visible and recoverable.

- A failed route never leaves the shell hidden.
- A failed modal presentation resets modal route state.
- Missing 3D or World Studio classes display a specific unavailable message and remain on Home.
- Missing host action APIs produce a diagnostic result rather than silently doing nothing.
- Duplicate installation attempts return the existing coordinator.
- Unexpected root-controller structure causes a fail-closed stock-host launch, not a partial overlay.

## Testing strategy

### Pure state tests

Cover:

- root-tab selection;
- Create tray toggle and every dismissal path;
- modal presentation and dismissal;
- non-root shell hiding and root restoration;
- failed-route rollback;
- account and settings return-to-tab behavior.

### Source contracts

Reject:

- `window.addSubview(shell.view)`;
- unmanaged full-window passthrough overlays;
- repeated 120-attempt refresh bursts;
- hidden-control success without visibility verification;
- stale `Build 846`–`Build 850` literals;
- global dark-view deletion;
- generic alert-window suppression;
- optimistic destination-state mutation before presentation success.

Require:

- root container installation;
- child-controller containment;
- explicit route result types;
- modal navigation wrappers with Back or Close;
- production 3D and World Studio controller names;
- bounded structural promotion suppression;
- Build 851 metadata consistency.

### UIKit interaction tests

On an iOS Simulator or physical device, automate where possible:

1. launch to Home with no visible legacy promotion;
2. show and dismiss the official Telegram card;
3. tap Join Channel and verify the official URL request;
4. toggle Create open and closed;
5. dismiss Create by outside tap and tab change;
6. open and close Settings;
7. open and close Account without spontaneous dismissal;
8. open Projects and Templates with no Home overlay;
9. open New Project and cancel;
10. open Import and cancel;
11. open 3D Studio and return;
12. open World Studio and return;
13. repeat all root-tab transitions 20 times;
14. background and foreground from every root tab;
15. verify no duplicate header, shell, tray, modal, or bottom navigation.

### Packaging tests

Require:

- exact baseline input hash;
- one Build 851 UI framework load command;
- existing extension load command preserved;
- expected root-container framework artifact;
- zero legacy branding occurrences;
- official URL present;
- release metadata consistency;
- no signing material in unsigned output;
- ZIP CRC pass;
- deterministic checksum and verification report.

## Performance constraints

- No continuous 100 ms or 150 ms refresh loops after installation.
- No repeated traversal of every view in every foreground window.
- No continuous reapplication of text colors or hidden states.
- No duplicate ambient animation when Home is not visible.
- Root-tab transitions must not allocate new root controllers.
- Modal presentation must not trigger shell reconstruction.

## Migration rules

The following Build 850 mechanisms are removed or retired:

- direct `window.addSubview(shell.view)` attachment;
- repeated `scheduleRefreshBurst()` polling as the primary lifecycle mechanism;
- asynchronous 24-pass surface refresh;
- optimistic `openNonRoot` before route success;
- hidden host-control action forwarding as the default route;
- generic text-based hiding of entire windows;
- user-visible hardcoded `Build 846` header text.

Reusable components are limited to presentation-only code that can be retained without the rejected ownership model:

- color and spacing tokens;
- spotlight cards;
- ambient field with lifecycle pause;
- Home visual sections;
- Tutorials visual sections;
- bottom-navigation visual component after state ownership is removed from it;
- official-channel card after adaptive constraints are corrected.

## Completion criteria

Build 851 is ready for physical-device testing only when all of the following are true:

1. Build 850 overlay integration paths are absent.
2. Root installation is idempotent and controller-owned.
3. Home and Tutorials render immediately without a one-second visual replacement.
4. Projects and Templates receive direct touch input with no Home overlay.
5. Create always closes through every specified path.
6. Settings and Account have reliable Back or Close behavior.
7. Account does not dismiss spontaneously.
8. New Project, Import, Camera, and Asset Library produce verified routes or explicit failures.
9. Production 3D and World Studio controllers open and return correctly.
10. The official Telegram card is readable and opens `https://t.me/aemotionios`.
11. No Blatant promotion, branding, URL, or legacy promotion window appears.
12. Visible and packaged metadata consistently report Build 851.
13. State tests, source contracts, Swift tests, iOS framework build, packaging verification, and ZIP CRC all pass.
14. The candidate is still reported as unsigned and not device-qualified until the user completes the physical-device matrix.

## Non-goals

Build 851 does not expand the 3D engine, World Studio renderer, Asset Library catalog, AI models, effect engine, export engine, or unrelated editor features. It restores a stable product shell and reliable entry into the existing implementations first.
