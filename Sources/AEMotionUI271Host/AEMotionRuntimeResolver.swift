#if canImport(UIKit)
import UIKit

@MainActor
enum AEMotionRuntimeResolver {
    static var hasInstalledRequiredRootHooks: Bool { true }

    @discardableResult
    static func install() -> Bool {
        AEMotionGlobalShellCoordinator.start()
        return true
    }

    static func refreshVisibleRootSurfaces() {
        AEMotionGlobalShellCoordinator.start()
    }
}
#endif
