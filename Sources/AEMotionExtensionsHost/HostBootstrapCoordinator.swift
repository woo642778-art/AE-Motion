#if canImport(UIKit)
import Foundation
import UIKit

@MainActor
enum HostBootstrapCoordinator {
    private static let maximumAttempts = 40
    private static let retryDelay: TimeInterval = 0.25

    private static var started = false
    private static var attemptCount = 0
    private static var runtimeInstalled = false
    private static var contextualInstalled = false
    private static var authInstalled = false
    private static var pendingRetry: DispatchWorkItem?
    private static var observerTokens: [NSObjectProtocol] = []

    static func start() {
        guard !started else {
            scheduleAttempt(after: 0)
            return
        }

        started = true
        observerTokens.append(
            NotificationCenter.default.addObserver(
                forName: UIApplication.didFinishLaunchingNotification,
                object: nil,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    scheduleAttempt(after: 0)
                }
            }
        )
        observerTokens.append(
            NotificationCenter.default.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    attemptCount = 0
                    scheduleAttempt(after: 0)
                    WatermarkStateRefresh.refreshVisibleHierarchy()
                }
            }
        )

        AuthenticationTimeoutGuard.start()
        WatermarkStateRefresh.start()
        scheduleAttempt(after: 0)
    }

    private static func scheduleAttempt(after delay: TimeInterval) {
        pendingRetry?.cancel()
        let workItem = DispatchWorkItem {
            Task { @MainActor in
                attemptInstall()
            }
        }
        pendingRetry = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private static func attemptInstall() {
        attemptCount += 1

        if !runtimeInstalled {
            runtimeInstalled = RuntimeResolver.install()
        }
        if !contextualInstalled {
            contextualInstalled = ContextualButtonInjector.installRuntimeHook()
        }
        if !authInstalled {
            authInstalled = GoogleSignInCallbackRepair.install()
        }

        if runtimeInstalled && contextualInstalled && authInstalled {
            pendingRetry = nil
            return
        }

        guard attemptCount < maximumAttempts else {
            pendingRetry = nil
            return
        }
        scheduleAttempt(after: retryDelay)
    }
}
#endif
