import Foundation

@_cdecl("AEMotionExtensionsInstall")
public func AEMotionExtensionsInstall() {
#if canImport(UIKit)
    Task.detached(priority: .utility) {
        RenderTemporaryFiles.cleanupStaleFiles()
    }
    _ = RuntimeResolver.install()
    Task { @MainActor in
        _ = ContextualButtonInjector.installRuntimeHook()
    }
#endif
}
