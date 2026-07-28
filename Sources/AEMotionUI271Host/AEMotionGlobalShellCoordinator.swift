#if canImport(UIKit)
import UIKit
import AEMotionExtensionsCore

@MainActor
enum AEMotionGlobalShellCoordinator {
    private struct WindowCandidate {
        let window: UIWindow
        let hostRoot: UIViewController
        let tabController: UITabBarController
        let selectedLeaf: UIViewController
        let selectedTab: AEMotionRootTab
    }

    private static let controllerMarkers: [AEMotionRootTab: [String]] = [
        .home: ["homevc", "homeviewvc"],
        .tutorials: ["tutorialsviewvc", "tutorialvc", "learning"],
        .projects: ["projectslistvc", "projectsvc"],
        .templates: ["templateslistvc", "templatesshowcasevc", "templatesvc"],
    ]

    private static let maximumInstallationAttempts = 32
    private static let retryDelay: TimeInterval = 0.25

    private static var hasStarted = false
    private static var installationAttempt = 0
    private static var observers: [NSObjectProtocol] = []
    private static var pendingInstallWorkItem: DispatchWorkItem?
    private static var installedContainer: AEMotionRootContainerViewController?
    private static weak var installedWindow: UIWindow?

    static func start() {
        guard installedContainer == nil else { return }
        guard !hasStarted else {
            scheduleInstallAttempt(resetAttempts: false)
            return
        }

        hasStarted = true
        let center = NotificationCenter.default
        for name in [
            UIApplication.didBecomeActiveNotification,
            UIWindow.didBecomeVisibleNotification,
            UIWindow.didBecomeKeyNotification,
        ] {
            let observer = center.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    scheduleInstallAttempt(resetAttempts: false)
                }
            }
            observers.append(observer)
        }
        scheduleInstallAttempt(resetAttempts: true)
    }

    private static func scheduleInstallAttempt(resetAttempts: Bool) {
        guard installedContainer == nil else { return }
        if resetAttempts {
            installationAttempt = 0
        }
        guard installationAttempt < maximumInstallationAttempts,
              pendingInstallWorkItem == nil else { return }

        let workItem = DispatchWorkItem {
            Task { @MainActor in
                pendingInstallWorkItem = nil
                installIfReady()
            }
        }
        pendingInstallWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + (installationAttempt == 0 ? 0.10 : retryDelay),
            execute: workItem
        )
    }

    private static func installIfReady() {
        guard installedContainer == nil else { return }
        installationAttempt += 1

        guard let candidate = preferredCandidate(), isReady(candidate) else {
            scheduleInstallAttempt(resetAttempts: false)
            return
        }

        let container = AEMotionRootContainerViewController(
            hostController: candidate.hostRoot,
            hostTabController: candidate.tabController,
            initialTab: candidate.selectedTab
        )
        candidate.window.rootViewController = container
        candidate.window.backgroundColor = AEMotionProductTheme.canvas
        container.loadViewIfNeeded()

        installedWindow = candidate.window
        installedContainer = container
        stopInstallationObservers()
        AEMotionLaunchBrandingSanitizer.sanitizeNow()
        AEMotionLaunchOverlay.markShellReady()
    }

    private static func preferredCandidate() -> WindowCandidate? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter {
                $0.activationState == .foregroundActive
                    || $0.activationState == .foregroundInactive
            }
            .flatMap(\.windows)
            .filter {
                !$0.isHidden
                    && $0.alpha > 0.01
                    && $0.windowLevel == .normal
                    && !$0.bounds.isEmpty
            }
            .compactMap { window -> WindowCandidate? in
                guard let root = window.rootViewController,
                      !(root is AEMotionRootContainerViewController),
                      let tabController = findTabController(from: root),
                      let selected = tabController.selectedViewController else {
                    return nil
                }
                let leaf = visibleLeaf(from: selected)
                guard let tab = selectedTab(for: leaf) else { return nil }
                return WindowCandidate(
                    window: window,
                    hostRoot: root,
                    tabController: tabController,
                    selectedLeaf: leaf,
                    selectedTab: tab
                )
            }
            .max { left, right in
                if left.window.isKeyWindow != right.window.isKeyWindow {
                    return !left.window.isKeyWindow && right.window.isKeyWindow
                }
                let leftArea = left.window.bounds.width * left.window.bounds.height
                let rightArea = right.window.bounds.width * right.window.bounds.height
                return leftArea < rightArea
            }
    }

    private static func isReady(_ candidate: WindowCandidate) -> Bool {
        guard UIApplication.shared.applicationState == .active,
              candidate.window.isKeyWindow,
              candidate.window.rootViewController === candidate.hostRoot,
              candidate.hostRoot.viewIfLoaded?.window === candidate.window,
              candidate.tabController.viewIfLoaded?.window === candidate.window,
              candidate.selectedLeaf.viewIfLoaded?.window === candidate.window,
              candidate.hostRoot.presentedViewController == nil,
              !candidate.hostRoot.isBeingPresented,
              !candidate.hostRoot.isBeingDismissed,
              (candidate.tabController.viewControllers?.count ?? 0) >= 4,
              !containsVisibleActivityIndicator(in: candidate.window),
              !containsLaunchNamedController(from: candidate.hostRoot) else {
            return false
        }
        return true
    }

    private static func stopInstallationObservers() {
        pendingInstallWorkItem?.cancel()
        pendingInstallWorkItem = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
    }

    private static func findTabController(from root: UIViewController) -> UITabBarController? {
        var queue: [UIViewController] = [root]
        var seen = Set<ObjectIdentifier>()
        while let controller = queue.first {
            queue.removeFirst()
            guard seen.insert(ObjectIdentifier(controller)).inserted else { continue }
            if let tabController = controller as? UITabBarController {
                return tabController
            }
            queue.append(contentsOf: controller.children)
        }
        return nil
    }

    private static func visibleLeaf(from controller: UIViewController) -> UIViewController {
        if let navigation = controller as? UINavigationController,
           let visible = navigation.visibleViewController {
            return visibleLeaf(from: visible)
        }
        if let tab = controller as? UITabBarController,
           let selected = tab.selectedViewController {
            return visibleLeaf(from: selected)
        }
        if let presented = controller.presentedViewController,
           !presented.isBeingDismissed {
            return visibleLeaf(from: presented)
        }
        return controller
    }

    private static func selectedTab(for controller: UIViewController) -> AEMotionRootTab? {
        for tab in AEMotionRootTab.allCases {
            guard let markers = controllerMarkers[tab],
                  matches(controller: controller, markers: markers) else { continue }
            return tab
        }
        return nil
    }

    private static func matches(
        controller: UIViewController,
        markers: [String]
    ) -> Bool {
        var queue: [UIViewController] = [controller]
        var seen = Set<ObjectIdentifier>()
        while let current = queue.first {
            queue.removeFirst()
            guard seen.insert(ObjectIdentifier(current)).inserted else { continue }
            let name = String(describing: type(of: current)).lowercased()
            if markers.contains(where: name.contains) {
                return true
            }
            queue.append(contentsOf: current.children)
            if let navigation = current as? UINavigationController {
                queue.append(contentsOf: navigation.viewControllers)
            }
        }
        return false
    }

    private static func containsVisibleActivityIndicator(in view: UIView) -> Bool {
        guard !view.isHidden, view.alpha > 0.01 else { return false }
        if let indicator = view as? UIActivityIndicatorView,
           indicator.isAnimating,
           indicator.window != nil {
            return true
        }
        return view.subviews.contains(where: containsVisibleActivityIndicator)
    }

    private static func containsLaunchNamedController(
        from root: UIViewController
    ) -> Bool {
        var queue: [UIViewController] = [root]
        var seen = Set<ObjectIdentifier>()
        let launchMarkers = ["loading", "splash", "launch", "bootstrap"]
        while let controller = queue.first {
            queue.removeFirst()
            guard seen.insert(ObjectIdentifier(controller)).inserted else { continue }
            let name = String(describing: type(of: controller)).lowercased()
            if launchMarkers.contains(where: name.contains) {
                return true
            }
            queue.append(contentsOf: controller.children)
            if let presented = controller.presentedViewController,
               !presented.isBeingDismissed {
                queue.append(presented)
            }
        }
        return false
    }
}
#endif
