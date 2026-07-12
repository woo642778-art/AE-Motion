import Foundation

@_cdecl("AEMotionExtensionsInstall")
public func AEMotionExtensionsInstall() {
#if canImport(UIKit)
    _ = RuntimeResolver.install()
#endif
}
