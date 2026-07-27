import Foundation

#if canImport(Darwin)
import Darwin
#endif

final class AEMotionUI271BundleToken: NSObject {}

enum LegacyFrameworkLoader {
    nonisolated(unsafe) private static var handle: UnsafeMutableRawPointer?

    static func loadLegacyFramework() -> Bool {
        if handle != nil { return true }
#if canImport(Darwin)
        let frameworkBundle = Bundle(for: AEMotionUI271BundleToken.self)
        let legacyURL = frameworkBundle.bundleURL.appendingPathComponent("AEMotionExtensionsLegacy")
        guard FileManager.default.isExecutableFile(atPath: legacyURL.path) else { return false }
        guard let loaded = dlopen(legacyURL.path, RTLD_NOW | RTLD_GLOBAL) else { return false }
        handle = loaded
        return true
#else
        return false
#endif
    }
}
