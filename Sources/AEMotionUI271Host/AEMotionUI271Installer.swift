import Foundation

@_cdecl("AEMotionUI271Install")
public func AEMotionUI271Install() {
#if canImport(UIKit)
    guard LegacyFrameworkLoader.loadLegacyFramework() else { return }
    DispatchQueue.main.async {
        AEMotionUI271Installer.installRuntimeHooks()
    }
#else
    _ = LegacyFrameworkLoader.loadLegacyFramework()
#endif
}

enum AEMotionUI271Installer {
    @MainActor
    static func installRuntimeHooks() {
#if canImport(UIKit)
        _ = AEMotionRuntimeResolver.install()
#endif
    }
}
