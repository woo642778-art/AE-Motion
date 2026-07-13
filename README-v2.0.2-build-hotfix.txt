AE Motion Extensions v2.0.2 Build Hotfix

Root cause
- CategoryCollectionProxy is @MainActor because it implements UIKit data-source and delegate behavior.
- NSObject.responds(to:) and NSObject.forwardingTarget(for:) are nonisolated runtime overrides.
- Their implementations read originalDataSource and originalDelegate, which were actor-isolated weak properties.
- Swift 6 therefore rejected the iOS Release build.

Fix
- Mark only the two Objective-C runtime forwarding references as nonisolated(unsafe).
- Mark the two NSObject overrides explicitly nonisolated.
- Snapshot the weak references into local variables before selector checks.
- Keep the rest of CategoryCollectionProxy @MainActor.

The unsafe isolation escape is intentionally narrow. These two weak references are initialized once and are used only for Objective-C message-forwarding decisions. UI mutation remains main-actor isolated.

No feature behavior, tool placement, theme, Add Effects metadata, preset data or render code is changed.
