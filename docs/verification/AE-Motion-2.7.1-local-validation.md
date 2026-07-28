# AE Motion 2.7.1 Local Validation Evidence

Date: 2026-07-27
Branch: `fix/home-shell-ui-restoration`
Release: 2.7.1
Build: 839

## Portable Swift validation

An isolated Swift 6.2.1 Linux harness was reconstructed from the branch's new 2.7.1 targets. It retained the same product/target boundaries while substituting markers only for the pre-existing repository modules that are outside the new UI scope.

Command:

```bash
swift test
```

Result:

- `HomeShellStateTests`: 3 executed
- Failures: 0
- Unexpected failures: 0
- Release identity verified as 2.7.1 Build 839
- Non-root navigation hiding and root restoration verified
- Create-tray state rules verified

## UI source parsing

Command:

```bash
for source in Sources/AEMotionUI271Host/*.swift; do
  swiftc -frontend -parse "$source"
done
```

Result: all new Swift source files parsed successfully with Swift 6.2.1.

This is syntax validation only. UIKit type checking still requires an Apple SDK and Xcode.

## Source-contract validation

Commands:

```bash
python3 scripts/test-ui271-home-contract.py
python3 scripts/test-ui271-runtime-contract.py
python3 scripts/test-ui271-visual-contract.py
python3 scripts/test-ui271-wrapper-contract.py
```

Results:

- Home shell ownership contract: pass
- Allowlisted runtime integration contract: pass
- Native visual and motion contract: pass
- Legacy wrapper contract: pass

## Packaging validation

Command:

```bash
python3 scripts/test-package-ui271-ipa.py
```

Result:

- Tests executed: 3
- Failures: 0
- In-place Mach-O install-name replacement: pass
- Wrapper and preserved legacy executable packaging: pass
- AE Motion 2.7.1 Build 839 metadata: pass
- Signature-material removal: pass
- ZIP CRC verification: pass
- Rejection of an unexpected base install name: pass

The packaging test uses synthetic Mach-O and IPA fixtures. It does not substitute for building the real arm64 wrapper.

## GitHub Actions status

Draft PR: #10

- Run `30231855118`: the macOS job completed as failure before exposing workflow steps or logs.
- Run `30232027596`: the Ubuntu `validate` job completed as failure before exposing workflow steps or logs; dependent `build-ios` was skipped.

The failure occurred before any repository command executed. No compiler, test, or source-contract failure was produced. Recent repository PR history records the same Actions behavior in other branches.

## Remaining release gate

The following are not yet verified:

- Xcode UIKit type checking
- generic arm64 iOS Release framework build
- real wrapper framework artifact
- packaging of the supplied `AE Motion 2.7(1).ipa` with that artifact
- Simulator interaction
- signed physical-iPhone launch and interaction
- memory, thermal, CPU, GPU, rotation, and device-specific layout

No final 2.7.1 IPA may be claimed until the arm64 wrapper artifact is produced and the real IPA packaging verification passes.
