import Foundation

@_cdecl("AEMotionUI272Install")
public func AEMotionUI272Install() {
#if canImport(UIKit)
    DispatchQueue.main.async {
        AEMotionUI272Installer.installRuntimeHooks()
    }
#endif
}

enum AEMotionUI272Installer {
    @MainActor
    static func installRuntimeHooks() {
#if canImport(UIKit)
        _ = AEMotionRuntimeResolver.install()
#endif
    }
}
