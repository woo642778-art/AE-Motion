AE Motion Extensions v2.0.1 build hotfix

Root cause
- PresetApplicationHostError was declared @MainActor while conforming to LocalizedError.
- In Swift 6, LocalizedError.errorDescription is a nonisolated protocol requirement.
- The actor-isolated property therefore could not satisfy the protocol during the iOS Release build.

Fix
- Remove @MainActor from the value-only PresetApplicationHostError enum.
- Keep PresetApplicationContext itself @MainActor.
- Add a Swift 6 compile regression test that extracts the actual enum source and type-checks it.
- Run that regression test in GitHub Actions before the iOS framework build.

No Preset Studio behavior, Add Effects categories, BCC search, render logic, or preset data model is changed by this hotfix.
