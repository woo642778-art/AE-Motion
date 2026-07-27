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
        guard !hasStarted else {
            AEMotionLaunchBrandingSanitizer.install()
            AEMotionGlobalShellCoordinator.start()
            return
        }
        hasStarted = true
        AEMotionLaunchBrandingSanitizer.install()
        AEMotionGlobalShellCoordinator.start()
    }
#else
    static func start() {}
#endif
}
