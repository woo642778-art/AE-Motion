import Foundation

@_cdecl("AEMotionExtensionsInstall")
public func AEMotionExtensionsInstall() {
#if canImport(UIKit)
    Task.detached(priority: .utility) {
        RenderTemporaryFiles.cleanupStaleFiles()
    }
    _ = RuntimeResolver.install()
    _ = ContextualButtonInjector.installRuntimeHook()
#endif
}
