# MacBook Pro A2289: minimal AE Motion development setup

This repository now generates a standalone iOS Simulator host. The host opens the existing Extensions & Scripts interface without modifying or repacking an IPA.

## What the user must do once

1. Update the Mac to the newest macOS version officially offered for the A2289.
2. Install a compatible Xcode release in `/Applications/Xcode.app`.
3. Open Xcode once, accept the license, and install one iOS Simulator runtime from **Xcode > Settings > Platforms**.
4. Install Homebrew from its official website if it is not already installed.
5. Clone this repository and run:

```bash
bash scripts/bootstrap-macos.sh
```

The bootstrap selects Xcode, completes its first-launch setup, installs the small command-line tool set from `Brewfile`, generates the test project, and runs environment diagnostics.

## Commands used after setup

```bash
make doctor       # verify Xcode, Swift, XcodeGen and Simulator availability
make generate     # regenerate the Xcode project from TestHost/project.yml
make test-core    # run cross-platform Swift tests
make test-ios     # run unit and UI tests in an available iPhone Simulator
make build-ios    # build the injectable iOS framework
make verify       # run all checks
```

Open the generated test app manually with:

```bash
open TestHost/AEMotionTestHost.xcodeproj
```

Select the `AEMotionTestHost` scheme and any installed iPhone Simulator. No Apple Developer account is required for Simulator execution.

## What is automated in GitHub

Pull requests and pushes to `main` run the existing source-contract tests, build the iOS framework, generate the Simulator host, launch it, open Extensions & Scripts, and save the `.xcresult` bundle and build log as workflow artifacts.

## What remains device-only

The Simulator host validates the extension UI, navigation, registry, crashes and many layout regressions. It cannot validate runtime injection into the original signed application, private host classes, App Store receipts, device-only codecs, or final IPA signing. Those checks remain a short real-device release gate.
