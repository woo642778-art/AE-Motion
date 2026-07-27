import Foundation

#if canImport(UIKit)
import UIKit
#endif

@_cdecl("AEMotionUI272Install")
public func AEMotionUI272Install() {
#if canImport(UIKit)
    DispatchQueue.main.async {
        AEMotionUI272Installer.start()
    }
#endif
}

enum AEMotionUI272Installer {
#if canImport(UIKit)
    @MainActor private static var hasStarted = false

    @MainActor
    static func start() {
        AEMotionLaunchOverlay.install()
        AEMotionLaunchBrandingSanitizer.install()
        AEMotionGlobalShellCoordinator.start()
        hasStarted = true
    }
#else
    static func start() {}
#endif
}
