# AE Motion v2.3 Shake and iPhone UI Crash Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce a single-framework unsigned recovery IPA that stops the three reported shake-effect table crashes and replaces the overlapping iPhone navigation button with a safe movable floating control.

**Architecture:** Preserve the current shader bodies for the first recovery candidate and normalize only the affected XML parameter-table contracts. Build the floating utilities control from Swift source inside `AEMotionExtensionsHost.framework`; do not binary-patch navigation selectors or add a second framework.

**Tech Stack:** Swift 6, UIKit, Objective-C runtime, Python 3, XML/GLSL descriptors, GitHub Actions macOS 15, unsigned IPA packaging.

## Global Constraints

- Minimum platform is iOS 15.
- Preserve bundle identifier `com.alightcreative.motion`.
- Preserve the main app executable byte-for-byte.
- Ship exactly one AE Motion framework: `AEMotionExtensionsHost.framework`.
- Do not bypass subscription, receipt, account or watermark entitlement checks.
- Do not label an effect device-qualified without physical-device evidence.

---

### Task 1: Add failing descriptor contract tests

**Files:**
- Create: `scripts/test-v23-shake-ui-contract.py`
- Modify: `.github/workflows/build-ios-framework.yml`

**Interfaces:**
- Consumes: `Effects/v2.3-batch-a/repairs/*.xml`
- Produces: a deterministic nonzero exit status for malformed UI contracts

- [ ] Assert the three crash-reported descriptors contain no empty or trailing section.
- [ ] Assert selector defaults match declared choices.
- [ ] Assert every spinner declares a supported numeric type.
- [ ] Assert `S_DissolveShake` contains no checkbox parameter.
- [ ] Assert the exact `S_Shake Ultra` thumbnail asset exists and has a PNG signature.
- [ ] Run the test and verify it fails against the current branch state.
- [ ] Commit as `test: define shake descriptor UI contract`.

### Task 2: Normalize the three descriptor UI contracts

**Files:**
- Create: `Effects/v2.3-batch-a/repairs/poseshake.xml`
- Create: `Effects/v2.3-batch-a/repairs/sshakeultra.xml`
- Create: `Effects/v2.3-batch-a/repairs/s_dissolveshake.xml`
- Create: `Effects/v2.3-batch-a/repairs/thumb/ultrashake.png.b64`
- Modify: `scripts/repair-v23-batch-a-effects.py`

**Interfaces:**
- Produces: `normalize_parameter_contract(path: Path) -> dict`

- [ ] Flatten UI section markers while preserving parameter order and IDs.
- [ ] Prefix labels with their former section names so grouping remains understandable.
- [ ] Add explicit `type="float"` to numeric spinners that omit it.
- [ ] Replace `motionBlur` checkbox with a numeric 0/1 selector.
- [ ] Change only the matching shader condition to numeric comparison.
- [ ] Decode the thumbnail during packaging to both `ultrashake.png` and `sshakeultra.png` compatibility paths.
- [ ] Re-run descriptor tests and verify they pass.
- [ ] Commit as `fix: normalize shake parameter table contracts`.

### Task 3: Add failing iPhone utilities-control tests

**Files:**
- Create: `scripts/test-v23-floating-utilities-contract.py`

**Interfaces:**
- Consumes: `ContextualButtonInjector.swift` and `FloatingUtilitiesButtonController.swift`

- [ ] Require an iPhone-specific floating-button path.
- [ ] Forbid appending the utilities item to `rightBarButtonItems` on the iPhone path.
- [ ] Require pan and long-press gestures.
- [ ] Require `UserDefaults` persistence and safe-area clamping.
- [ ] Run the test and verify failure.
- [ ] Commit as `test: define floating utilities control contract`.

### Task 4: Implement the floating utilities control

**Files:**
- Create: `Sources/AEMotionExtensionsHost/FloatingUtilitiesButtonController.swift`
- Modify: `Sources/AEMotionExtensionsHost/ContextualButtonInjector.swift`

**Interfaces:**
- Produces: `FloatingUtilitiesButtonController.install(in:menu:)`
- Produces: `FloatingUtilitiesButtonController.reclamp(in:)`

- [ ] Add a 44-point menu button to the editor view on iPhone.
- [ ] Constrain movement to a safe-area inset frame.
- [ ] Persist normalized position after pan completion.
- [ ] Reset position on long press.
- [ ] Re-clamp during editor layout updates.
- [ ] Use the existing navigation item on iPad only when space is sufficient.
- [ ] Run static tests and Swift parser/build checks.
- [ ] Commit as `fix: move utilities control out of iPhone navigation bar`.

### Task 5: Build and package the recovery candidate

**Files:**
- Modify: `.github/workflows/build-ios-framework.yml`
- Modify: `scripts/package-v23-batch-a-candidate.sh`
- Modify: `scripts/verify-v23-batch-a-package.py`

**Interfaces:**
- Produces: `AE-Motion-v2.3-shake-ui-recovery-unsigned.ipa`

- [ ] Build the source framework on macOS 15.
- [ ] Apply only the normalized descriptors and thumbnail asset to the stabilized base IPA.
- [ ] Replace only `AEMotionExtensionsHost.framework`.
- [ ] Remove signing and provisioning material.
- [ ] Verify one AE Motion framework, unchanged main executable, XML validity, PNG signatures and ZIP integrity.
- [ ] Generate verification JSON and SHA-256 checksum files.

### Task 6: Sequential device qualification

**Files:**
- Create: `docs/v2.3-shake-ui-recovery-device-checklist.md`

- [ ] Verify launch and editor entry.
- [ ] Verify the floating control does not overlap render controls and remains movable after rotation.
- [ ] Apply `S_Pos Shake`; stop immediately on failure.
- [ ] Apply `S_Shake Ultra`; stop immediately on failure.
- [ ] Apply `S_DissolveShake`; stop immediately on failure.
- [ ] Verify five-second preview and export for each passing effect.
- [ ] Record a fresh `.ips` for any failure before changing shader code.