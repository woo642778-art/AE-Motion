import Foundation

@_cdecl("AEMotionExtensionsInstall")
public func AEMotionExtensionsInstall() {
#if canImport(UIKit)
    Task.detached(priority: .utility) {
        RenderTemporaryFiles.cleanupStaleFiles()
    }
    Task { @MainActor in
        HostBootstrapCoordinator.start()
    }
#endif
}
