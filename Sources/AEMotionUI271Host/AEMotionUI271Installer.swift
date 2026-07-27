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
    @MainActor private static var hasInstalled = false
    @MainActor private static var retryCount = 0
    @MainActor private static var retryScheduled = false
    @MainActor private static var observers: [NSObjectProtocol] = []
    private static let maximumRetryCount = 600
    private static let retryDelay: TimeInterval = 0.10

    @MainActor
    static func start() {
        AEMotionLaunchBrandingSanitizer.install()

        if !hasStarted {
            hasStarted = true
            let center = NotificationCenter.default
            observers.append(center.addObserver(
                forName: UIApplication.didFinishLaunchingNotification,
                object: nil,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    retryCount = 0
                    attemptInstall()
                }
            })
            observers.append(center.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    retryCount = 0
                    attemptInstall()
                }
            })
        }
        attemptInstall()
    }

    @MainActor
    private static func attemptInstall() {
        retryScheduled = false
        _ = AEMotionRuntimeResolver.install()
        hasInstalled = AEMotionRuntimeResolver.hasInstalledRequiredRootHooks

        if hasInstalled {
            retryCount = 0
            AEMotionRuntimeResolver.refreshVisibleRootSurfaces()
            return
        }

        guard retryCount < maximumRetryCount else { return }
        retryCount += 1
        guard !retryScheduled else { return }
        retryScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay) {
            Task { @MainActor in attemptInstall() }
        }
    }
#else
    static func start() {}
#endif
}
