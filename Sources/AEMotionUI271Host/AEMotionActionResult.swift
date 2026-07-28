#if canImport(UIKit)
import Foundation
import AEMotionExtensionsCore

@MainActor
enum AEMotionActionResult: Equatable {
    case opened(AEMotionNonRootRoute)
    case requiresOpenProject
    case unavailable(String)
    case failed(String)
}
#endif
