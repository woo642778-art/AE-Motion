#if canImport(UIKit)
import Foundation
import UIKit

@MainActor
enum AuthenticationTimeoutGuard {
    private static let timeout: TimeInterval = 25

    private static var started = false
    private static var pendingExternalAuth = false
    private static var callbackHandled = false
    private static var timeoutWorkItem: DispatchWorkItem?
    private static var observerTokens: [NSObjectProtocol] = []

    static func start() {
        guard !started else { return }
        started = true

        observerTokens.append(
            NotificationCenter.default.addObserver(
                forName: UIApplication.willResignActiveNotification,
                object: nil,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    guard let controller = visibleController(), isAuthenticationController(controller) else {
                        return
                    }
                    pendingExternalAuth = true
                    callbackHandled = false
                    timeoutWorkItem?.cancel()
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
                    scheduleTimeoutIfNeeded()
                }
            }
        )
    }

    static func noteCallbackHandled() {
        callbackHandled = true
        pendingExternalAuth = false
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
    }

    private static func scheduleTimeoutIfNeeded() {
        guard pendingExternalAuth, !callbackHandled else { return }

        timeoutWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            Task { @MainActor in
                handleTimeout()
            }
        }
        timeoutWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: workItem)
    }

    private static func handleTimeout() {
        guard pendingExternalAuth,
              !callbackHandled,
              let controller = visibleController(),
              isAuthenticationController(controller),
              containsAnimatingIndicator(controller.view) else {
            return
        }

        stopAnimatingIndicators(controller.view)
        pendingExternalAuth = false
        timeoutWorkItem = nil

        guard !(controller.presentedViewController is UIAlertController) else { return }
        let alert = UIAlertController(
            title: "Sign-in Didn't Finish",
            message: "Google sign-in returned without completing. Try Google again, or use Apple or email sign-in when available.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        controller.present(alert, animated: true)
    }

    private static func visibleController() -> UIViewController? {
        let keyWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
        return deepestVisibleController(from: keyWindow?.rootViewController)
    }

    private static func deepestVisibleController(from controller: UIViewController?) -> UIViewController? {
        guard let controller else { return nil }
        if let presented = controller.presentedViewController {
            return deepestVisibleController(from: presented)
        }
        if let navigation = controller as? UINavigationController {
            return deepestVisibleController(from: navigation.visibleViewController)
        }
        if let tab = controller as? UITabBarController {
            return deepestVisibleController(from: tab.selectedViewController)
        }
        return controller
    }

    private static func isAuthenticationController(_ controller: UIViewController) -> Bool {
        let name = String(describing: type(of: controller)).lowercased()
        return name.contains("authpicker")
            || name.contains("signin")
            || name.contains("authentication")
            || name.contains("oauth")
    }

    private static func containsAnimatingIndicator(_ view: UIView) -> Bool {
        if let indicator = view as? UIActivityIndicatorView, indicator.isAnimating {
            return true
        }
        return view.subviews.contains(where: containsAnimatingIndicator)
    }

    private static func stopAnimatingIndicators(_ view: UIView) {
        if let indicator = view as? UIActivityIndicatorView {
            indicator.stopAnimating()
        }
        view.subviews.forEach(stopAnimatingIndicators)
    }
}
#endif
