# AE Motion Build 851 Structural UI Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Build 846–850 full-window overlay architecture with a controller-owned Build 851 shell that preserves host navigation, routes actions explicitly, restores Settings/Account/3D/World flows, and suppresses only the verified legacy promotion surface.

**Architecture:** Install exactly one `AEMotionRootContainerViewController` after the verified host root tab controller is available, retain the original host root as a child, and make one route coordinator the sole owner of tab, modal, create-tray, and non-root state. Home and Tutorials are source-owned; Projects and Templates remain host-owned. Modal and tool actions return explicit success or failure before route state changes.

**Tech Stack:** Swift 6, UIKit, Swift Package Manager, GitHub Actions, Python packaging and Mach-O verification scripts.

## Global Constraints

- Marketing version remains `2.7.2`; candidate build is `851`.
- Work only on branch `fix/2.7.2-recovery`.
- Do not use unmanaged `window.addSubview(shell.view)` attachment.
- Do not use continuous refresh bursts after installation.
- Do not treat hidden or detached host controls as successful routes.
- Preserve the existing host root, `AEMotionExtensionsHost.framework`, and compatibility dylib unless a verified packaging contract says otherwise.
- Official Telegram URL is exactly `https://t.me/aemotionios`.
- Output remains unsigned and not device-qualified until physical-device verification.

---

### Task 1: Build 851 route state and reducer

**Files:**
- Create: `Sources/AEMotionExtensionsCore/AEMotionRouteState.swift`
- Create: `Tests/AEMotionExtensionsCoreTests/AEMotionRouteStateTests.swift`
- Modify: `Sources/AEMotionExtensionsCore/AEMotionRelease.swift`
- Modify: `Tests/AEMotionExtensionsCoreTests/HomeShellStateTests.swift`

**Interfaces:**
- Produces: `AEMotionRootTab`, `AEMotionModalRoute`, `AEMotionNonRootRoute`, `AEMotionRouteState`, `AEMotionRouteEvent`, `AEMotionRouteReducer.reduce(state:event:)`.
- Invariant: create tray, modal route, and non-root route are mutually exclusive.

- [ ] **Step 1: Write failing reducer tests**

Cover tab selection, create toggle, outside-tap dismissal, modal opening, modal dismissal to the previous tab, non-root opening only after success, and failed-route rollback.

- [ ] **Step 2: Run `swift test` and verify the new test target fails because the route types do not exist.**

- [ ] **Step 3: Implement the route model and reducer.**

Use explicit state:

```swift
public struct AEMotionRouteState: Equatable, Sendable {
    public var selectedTab: AEMotionRootTab
    public var modal: AEMotionModalRoute?
    public var nonRoot: AEMotionNonRootRoute?
    public var isCreateTrayPresented: Bool
}
```

Reducer rules must close the create tray before every tab, modal, non-root, and background transition.

- [ ] **Step 4: Set `AEMotionRelease.buildNumber = 851` and update release identity tests.**

- [ ] **Step 5: Run `swift test`; expected result: all core tests pass.**

- [ ] **Step 6: Commit `feat: add Build 851 route state`.**

---

### Task 2: Replace polling with one-shot root installation

**Files:**
- Replace: `Sources/AEMotionUI271Host/AEMotionGlobalShellCoordinator.swift`
- Modify: `Sources/AEMotionUI271Host/AEMotionUI271Installer.swift`
- Create: `scripts/test-ui272-build851-root-installation.py`

**Interfaces:**
- Consumes: `AEMotionRouteState` from Task 1.
- Produces: `AEMotionGlobalShellCoordinator.start()`, `installIfReady()`, and one retained `AEMotionRootContainerViewController` per app window.

- [ ] **Step 1: Write a failing source contract.**

Reject:

```text
window.addSubview(shell.view)
scheduleRefreshBurst
for attempt in 0..<120
```

Require one `window.rootViewController = container` assignment, `addChild`, `didMove(toParent:)`, and idempotent installation state.

- [ ] **Step 2: Run the contract and verify it fails against Build 850 code.**

- [ ] **Step 3: Replace the coordinator with a bounded readiness observer.**

Observe application activation and window visibility only until installation succeeds. Verify the expected host `UITabBarController`, no presented modal, and no loading or promotion surface. Install once, unregister observers, and retain the container.

- [ ] **Step 4: Run the contract and Swift parser; expected result: pass.**

- [ ] **Step 5: Commit `refactor: install Build 851 root container once`.**

---

### Task 3: Make the root container the sole shell owner

**Files:**
- Replace: `Sources/AEMotionUI271Host/AEMotionRootContainerViewController.swift`
- Replace: `Sources/AEMotionUI271Host/AEMotionShellViewController.swift`
- Create: `Sources/AEMotionUI271Host/AEMotionShellContentController.swift`
- Create: `Sources/AEMotionUI271Host/AEMotionCreateTrayController.swift`
- Create: `scripts/test-ui272-build851-shell-ownership.py`

**Interfaces:**
- Root container owns host child, shell child, route state, host-tab selection, modal presentation, and shell visibility.
- Shell exposes typed closures only: `onSelectTab`, `onToggleCreate`, `onDismissCreate`, `onAction`, `onSettings`, `onAccount`.

- [ ] **Step 1: Write a failing ownership contract.**

Require child-controller containment and reject unmanaged full-screen passthrough hit testing.

- [ ] **Step 2: Implement root composition.**

Home and Tutorials occupy the source-owned content region. Projects and Templates show the host tab controller content directly between the AE Motion header and bottom navigation. Hidden shell regions must have interaction disabled.

- [ ] **Step 3: Implement Create tray dismissal paths.**

Close on center-button retap, outside tap, tab change, action selection, modal presentation, non-root route, background, and shell hide.

- [ ] **Step 4: Remove hardcoded Build literals and render `AEMotionRelease.buildNumber`.**

- [ ] **Step 5: Run parser and ownership contract; expected result: pass.**

- [ ] **Step 6: Commit `refactor: give Build 851 shell single ownership`.**

---

### Task 4: Add explicit action routing and verified destinations

**Files:**
- Replace: `Sources/AEMotionUI271Host/AEMotionProjectActionCoordinator.swift`
- Replace: `Sources/AEMotionUI271Host/AEMotionStudioRouter.swift`
- Create: `Sources/AEMotionUI271Host/AEMotionActionRouter.swift`
- Create: `Sources/AEMotionUI271Host/AEMotionActionResult.swift`
- Create: `scripts/test-ui272-build851-action-routing.py`

**Interfaces:**

```swift
enum AEMotionActionResult {
    case opened(AEMotionNonRootRoute)
    case requiresOpenProject
    case unavailable(String)
    case failed(String)
}
```

`perform(_:from:completion:)` changes route state only after the destination is present or pushed.

- [ ] **Step 1: Write a failing routing contract.**

Reject unconditional hidden-control `sendActions` success. Require visibility, enabled state, current-window attachment, and destination verification for fallback controls.

- [ ] **Step 2: Implement direct 3D and World routes.**

Open `ThreeDStudioProjectBrowserViewController` and `WorldStudioProjectBrowserViewController` with an explicit navigation Back button.

- [ ] **Step 3: Implement New Project, Import, Camera, Asset Library, Continue Editing, and Quick Tools results.**

Quick Tools return `requiresOpenProject` unless `ProjectEditVC` is active. Failed routes leave the prior root state unchanged and display a recoverable alert.

- [ ] **Step 4: Run routing contract and Swift parser; expected result: pass.**

- [ ] **Step 5: Commit `feat: add verified Build 851 action router`.**

---

### Task 5: Restore Settings and Account modal ownership

**Files:**
- Create: `Sources/AEMotionUI271Host/AEMotionModalPresentationCoordinator.swift`
- Modify: `Sources/AEMotionUI271Host/AEMotionRootContainerViewController.swift`
- Create: `scripts/test-ui272-build851-modal-routing.py`

**Interfaces:**
- `presentSettings(from:completion:)`
- `presentAccount(from:completion:)`
- Modal coordinator conforms to `UIAdaptivePresentationControllerDelegate` and reports dismissal exactly once.

- [ ] **Step 1: Write a failing modal contract.**

Require `SettingsNC`, `MyAccountVC`, navigation wrappers, explicit Close actions, and presentation-controller delegate handling.

- [ ] **Step 2: Implement one-at-a-time modal presentation.**

Pause root route changes while a modal is active. Account and Settings return to the exact prior selected tab.

- [ ] **Step 3: Run parser and modal contract; expected result: pass.**

- [ ] **Step 4: Commit `fix: restore stable Settings and Account modals`.**

---

### Task 6: Replace promotion handling with bounded structural suppression

**Files:**
- Replace: `Sources/AEMotionUI271Host/AEMotionLaunchBrandingSanitizer.swift`
- Replace: `Sources/AEMotionUI271Host/AEMotionLaunchOverlay.swift`
- Modify: `Sources/AEMotionUI271Host/AEMotionRootContainerViewController.swift`
- Create: `scripts/test-ui272-build851-promotion-contract.py`

**Interfaces:**
- `AEMotionLegacyPromotionSuppressor.start()` runs for a bounded startup interval and stops permanently.
- `AEMotionOfficialChannelPresenter.presentIfNeeded(from:)` presents one adaptive source-controlled modal after root installation.

- [ ] **Step 1: Write failing suppression and layout contracts.**

Reject generic dark-window deletion, unbounded observers, unmanaged window overlays, and narrow intrinsic-width cards. Require official URL, safe-area width constraints, scrollable content, and coexistence prevention with Create tray.

- [ ] **Step 2: Implement verified structural fingerprint suppression.**

Only dismiss a non-main promotion controller/window matching promotion class or legacy label/button structure. Do not affect Settings, Account, editor, export, system alerts, or AE Motion official-channel UI.

- [ ] **Step 3: Implement official-channel modal inside the root container.**

Use readable compact-width constraints and explicit Join/Continue actions.

- [ ] **Step 4: Run parser and promotion contract; expected result: pass.**

- [ ] **Step 5: Commit `fix: isolate legacy and official promotion flows`.**

---

### Task 7: Package Build 851 without restoring legacy branding

**Files:**
- Create: `scripts/package-ui272-build851-ipa.py`
- Modify: `scripts/build-ios-framework.sh`
- Modify: `.github/workflows/build-ios-framework.yml`
- Modify: `scripts/test-ui272-framework-contract.py`
- Modify: `scripts/test-ui272-no-legacy-loader-contract.py`
- Modify: `scripts/test-ui272-device-regression-contract.py`
- Create: `scripts/test-ui272-build851-package-contract.py`

**Interfaces:**
- Build number and visible metadata are `851` everywhere.
- Packager preserves host initialization and compatibility code while enforcing zero legacy branding occurrences.

- [ ] **Step 1: Write the failing package contract.**

Require zero app-wide UTF-8/UTF-16 occurrences of `Blatant`, `Cracked By`, and `t.me/blatants`; require official URL; preserve host initializer bytes and existing extension hashes.

- [ ] **Step 2: Implement Build 851 packaging.**

Do not patch host initializers. Replace byte-safe branding and URL data only, preserve load commands required by the verified baseline, inject the Build 851 framework once, and remove signing material.

- [ ] **Step 3: Update framework and app metadata to `2.7.2 (851)`.**

- [ ] **Step 4: Run package unit tests; expected result: pass.**

- [ ] **Step 5: Commit `build: package AE Motion 2.7.2 Build 851`.**

---

### Task 8: CI, artifact verification, and physical-device candidate handoff

**Files:**
- Modify: `.github/workflows/build-ios-framework.yml`
- Create: `docs/releases/AE_Motion_2.7.2_Build_851_Verification.md`

**Interfaces:**
- Produces `AEMotionUI272-iOS-2.7.2-build851` framework artifact and unsigned Build 851 IPA candidate.

- [ ] **Step 1: Run all Swift tests, source contracts, Swift parser checks, and iOS arm64 Release build in GitHub Actions.**

- [ ] **Step 2: Download the successful framework artifact.**

- [ ] **Step 3: Package the IPA from the exact approved baseline hash.**

- [ ] **Step 4: Run independent verification.**

Verify ZIP CRC, file-count delta, Mach-O load commands, framework IDs, version agreement, legacy-string count, official URL, preserved host/extension hashes, and absence of signing material.

- [ ] **Step 5: Record limitations.**

State explicitly that Settings, Account, Create tray, Projects, Templates, 3D, World Studio, and official-channel interactions require physical-device validation.

- [ ] **Step 6: Commit `docs: add Build 851 verification report`.**
