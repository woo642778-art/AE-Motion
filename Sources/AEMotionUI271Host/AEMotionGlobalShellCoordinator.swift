#if canImport(UIKit)
import UIKit
import AEMotionExtensionsCore

@MainActor
enum AEMotionGlobalShellCoordinator {
    private struct WindowCandidate {
        let window: UIWindow
        let hostRoot: UIViewController
        let tabController: UITabBarController
        let leaf: UIViewController
        let exactTab: HomeShellTab?
        let area: CGFloat
    }

    private static let controllerMarkers: [HomeShellTab: [String]] = [
        .home: ["homevc", "homeviewvc"],
        .tutorials: ["tutorialsviewvc", "tutorialvc", "learning"],
        .projects: ["projectslistvc", "projectsvc"],
        .templates: ["templateslistvc", "templatesshowcasevc", "templatesvc"],
    ]

    private static let requiredStableCandidateCount = 6
    private static var hasStarted = false
    private static var observers: [NSObjectProtocol] = []
    private static var refreshGeneration = 0
    private static var adapters: [ObjectIdentifier: AEMotionHostSurfaceAdapter] = [:]
    private static var stableWindowIdentifier: ObjectIdentifier?
    private static var stableTabIdentifier: ObjectIdentifier?
    private static var stableLeafIdentifier: ObjectIdentifier?
    private static var stableCandidateCount = 0
    private static weak var shellWindow: UIWindow?
    private static var shellConstraints: [NSLayoutConstraint] = []

    static func start() {
        guard !hasStarted else {
            scheduleRefreshBurst()
            return
        }
        hasStarted = true

        let center = NotificationCenter.default
        for name in [
            UIApplication.didBecomeActiveNotification,
            UIWindow.didBecomeVisibleNotification,
            UIWindow.didBecomeKeyNotification,
        ] {
            observers.append(center.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { _ in
                Task { @MainActor in scheduleRefreshBurst() }
            })
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.50) {
            scheduleRefreshBurst()
        }
    }

    private static func scheduleRefreshBurst() {
        refreshGeneration += 1
        let generation = refreshGeneration
        for attempt in 0..<120 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35 + Double(attempt) * 0.15) {
                guard generation == refreshGeneration else { return }
                refreshVisibleShell()
            }
        }
    }

    private static func refreshVisibleShell() {
        guard UIApplication.shared.applicationState == .active,
              let candidate = preferredCandidate() else {
            resetStableCandidate()
            return
        }

        if shellWindow == nil {
            guard isHostWorkspaceReady(candidate) else {
                resetStableCandidate()
                return
            }
            recordStableCandidate(candidate)
            guard stableCandidateCount >= requiredStableCandidateCount else { return }
            attachShell(to: candidate.window)
        } else if shellWindow !== candidate.window {
            guard isHostWorkspaceReady(candidate) else { return }
            recordStableCandidate(candidate)
            guard stableCandidateCount >= requiredStableCandidateCount else { return }
            attachShell(to: candidate.window)
        }

        let tabController = candidate.tabController
        if shouldDetachShell(for: candidate.leaf, in: tabController) {
            hideShell()
            return
        }

        guard let tab = candidate.exactTab else {
            hideShell()
            return
        }

        tabController.tabBar.isHidden = true
        tabController.tabBar.isUserInteractionEnabled = false
        tabController.view.backgroundColor = AEMotionProductTheme.canvas
        candidate.window.backgroundColor = AEMotionProductTheme.canvas

        let activeAdapter = adapter(for: candidate.leaf, tab: tab)
        activeAdapter?.prepareForRootPresentation()

        let shell = AEMotionShellViewController.shared
        shell.routeHandler = { target in
            route(target, in: tabController)
        }
        shell.actionHandler = { action in
            if activeAdapter?.perform(action) == true { return }
            if let home = homeController(in: tabController) {
                let homeAdapter = adapter(for: home, tab: .home)
                homeAdapter?.prepareForRootPresentation()
                _ = homeAdapter?.perform(action)
            }
        }
        shell.settingsHandler = {
            presentStoryboard(named: "SettingsNC", from: tabController)
        }
        shell.profileHandler = {
            presentStoryboard(named: "MyAccountVC", from: tabController)
        }
        shell.view.isHidden = false
        shell.configure(tab: tab, showsHomeContent: tab == .home)
        candidate.window.bringSubviewToFront(shell.view)
        AEMotionLaunchBrandingSanitizer.sanitizeNow()
        AEMotionLaunchOverlay.markShellReady()
    }

    private static func preferredCandidate() -> WindowCandidate? {
        let candidates: [WindowCandidate] = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .compactMap { window in
                guard !window.isHidden,
                      window.alpha > 0.01,
                      window.windowLevel == .normal,
                      let root = window.rootViewController,
                      let tabController = findTabController(from: root),
                      let selected = tabController.selectedViewController else { return nil }

                let leaf = visibleLeaf(from: selected)
                let exactTab = verifiedTab(for: leaf)
                let area = window.bounds.width * window.bounds.height
                return WindowCandidate(
                    window: window,
                    hostRoot: root,
                    tabController: tabController,
                    leaf: leaf,
                    exactTab: exactTab,
                    area: area
                )
            }

        return candidates.max { left, right in
            if left.window.isKeyWindow != right.window.isKeyWindow {
                return !left.window.isKeyWindow && right.window.isKeyWindow
            }
            return left.area < right.area
        }
    }

    private static func isHostWorkspaceReady(_ candidate: WindowCandidate) -> Bool {
        let window = candidate.window
        let tabController = candidate.tabController

        guard window.isKeyWindow,
              window.rootViewController === candidate.hostRoot,
              tabController.viewIfLoaded?.window === window,
              candidate.leaf.viewIfLoaded?.window === window,
              !window.bounds.isEmpty,
              tabController.viewControllers?.count ?? 0 >= 4,
              candidate.exactTab != nil,
              isVerifiedRootController(candidate.leaf),
              candidate.hostRoot.presentedViewController == nil,
              !candidate.hostRoot.isBeingPresented,
              !candidate.hostRoot.isBeingDismissed,
              !containsVisibleActivityIndicator(in: window),
              !containsLaunchNamedController(from: candidate.hostRoot),
              !hasBlockingLaunchOverlay(in: window, hostRoot: candidate.hostRoot) else {
            return false
        }
        return true
    }

    private static func isVerifiedRootController(_ controller: UIViewController) -> Bool {
        verifiedTab(for: controller) != nil
    }

    private static func verifiedTab(for controller: UIViewController) -> HomeShellTab? {
        for tab in [HomeShellTab.home, .tutorials, .projects, .templates] {
            guard let markers = controllerMarkers[tab] else { continue }
            if matches(controller: controller, markers: markers) { return tab }
        }
        return nil
    }

    private static func recordStableCandidate(_ candidate: WindowCandidate) {
        let windowID = ObjectIdentifier(candidate.window)
        let tabID = ObjectIdentifier(candidate.tabController)
        let leafID = ObjectIdentifier(candidate.leaf)
        if stableWindowIdentifier == windowID,
           stableTabIdentifier == tabID,
           stableLeafIdentifier == leafID {
            stableCandidateCount += 1
            return
        }
        stableWindowIdentifier = windowID
        stableTabIdentifier = tabID
        stableLeafIdentifier = leafID
        stableCandidateCount = 1
    }

    private static func resetStableCandidate() {
        stableWindowIdentifier = nil
        stableTabIdentifier = nil
        stableLeafIdentifier = nil
        stableCandidateCount = 0
    }

    private static func attachShell(to window: UIWindow) {
        let shell = AEMotionShellViewController.shared
        shell.loadViewIfNeeded()

        if shell.view.superview !== window {
            NSLayoutConstraint.deactivate(shellConstraints)
            shellConstraints.removeAll()
            shell.view.removeFromSuperview()
            shell.view.translatesAutoresizingMaskIntoConstraints = false
            window.addSubview(shell.view)
            shellConstraints = [
                shell.view.leadingAnchor.constraint(equalTo: window.leadingAnchor),
                shell.view.trailingAnchor.constraint(equalTo: window.trailingAnchor),
                shell.view.topAnchor.constraint(equalTo: window.topAnchor),
                shell.view.bottomAnchor.constraint(equalTo: window.bottomAnchor),
            ]
            NSLayoutConstraint.activate(shellConstraints)
        }
        shellWindow = window
        shell.view.isHidden = false
        window.bringSubviewToFront(shell.view)
    }

    private static func hideShell() {
        let shell = AEMotionShellViewController.shared
        guard shell.isViewLoaded else { return }
        shell.prepareForHiddenState()
        shell.view.isHidden = true
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

    private static func containsLaunchNamedController(from root: UIViewController) -> Bool {
        var queue: [UIViewController] = [root]
        var seen = Set<ObjectIdentifier>()
        let launchMarkers = ["loading", "splash", "launch", "bootstrap"]
        while !queue.isEmpty {
            let controller = queue.removeFirst()
            guard seen.insert(ObjectIdentifier(controller)).inserted else { continue }
            let name = String(describing: type(of: controller)).lowercased()
            if launchMarkers.contains(where: name.contains) { return true }
            queue.append(contentsOf: controller.children)
            if let presented = controller.presentedViewController,
               !presented.isBeingDismissed {
                queue.append(presented)
            }
        }
        return false
    }

    private static func hasBlockingLaunchOverlay(
        in window: UIWindow,
        hostRoot: UIViewController
    ) -> Bool {
        guard hostRoot.isViewLoaded else { return true }
        let rootView = hostRoot.view!
        let windowArea = max(1, window.bounds.width * window.bounds.height)

        func containsBlockingOverlay(_ view: UIView) -> Bool {
            if view === rootView || view.isDescendant(of: rootView) {
                return false
            }
            if rootView.isDescendant(of: view) {
                return view.subviews.contains(where: containsBlockingOverlay)
            }
            guard !view.isHidden,
                  view.alpha > 0.01,
                  view.isUserInteractionEnabled else { return false }

            let visibleFrame = view.convert(view.bounds, to: window).intersection(window.bounds)
            guard !visibleFrame.isNull, !visibleFrame.isEmpty else { return false }
            let coverage = (visibleFrame.width * visibleFrame.height) / windowArea
            if coverage >= 0.55 { return true }
            return view.subviews.contains(where: containsBlockingOverlay)
        }

        return window.subviews.contains(where: containsBlockingOverlay)
    }

    private static func findTabController(from root: UIViewController) -> UITabBarController? {
        var queue: [UIViewController] = [root]
        var seen = Set<ObjectIdentifier>()
        while !queue.isEmpty {
            let controller = queue.removeFirst()
            guard seen.insert(ObjectIdentifier(controller)).inserted else { continue }
            if let tab = controller as? UITabBarController { return tab }
            queue.append(contentsOf: controller.children)
            if let presented = controller.presentedViewController,
               !presented.isBeingDismissed {
                queue.append(presented)
            }
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

    private static func index(for tab: HomeShellTab, in tabController: UITabBarController) -> Int? {
        guard tab != .create,
              let controllers = tabController.viewControllers,
              let markers = controllerMarkers[tab] else { return nil }
        return controllers.firstIndex(where: { matches(controller: $0, markers: markers) })
    }

    private static func matches(controller: UIViewController, markers: [String]) -> Bool {
        var queue: [UIViewController] = [controller]
        var seen = Set<ObjectIdentifier>()
        while !queue.isEmpty {
            let current = queue.removeFirst()
            guard seen.insert(ObjectIdentifier(current)).inserted else { continue }
            let className = String(describing: type(of: current)).lowercased()
            if markers.contains(where: { className.contains($0) }) { return true }
            queue.append(contentsOf: current.children)
            if let navigation = current as? UINavigationController {
                queue.append(contentsOf: navigation.viewControllers)
            }
        }
        return false
    }

    private static func shouldDetachShell(
        for leaf: UIViewController,
        in tabController: UITabBarController
    ) -> Bool {
        let name = String(describing: type(of: leaf)).lowercased()
        let nonRootMarkers = [
            "projecteditvc",
            "threedworkspaceviewcontroller",
            "worldworkspaceviewcontroller",
            "studioscene",
            "editorviewcontroller",
            "templatepreview",
            "export",
            "render",
            "settingsvc",
            "myaccountvc",
        ]
        if nonRootMarkers.contains(where: { name.contains($0) }) { return true }

        if let navigation = tabController.selectedViewController as? UINavigationController,
           navigation.viewControllers.count > 1,
           let root = navigation.viewControllers.first {
            let rootName = String(describing: type(of: root)).lowercased()
            if name != rootName { return true }
        }
        return false
    }

    private static func adapter(
        for controller: UIViewController,
        tab: HomeShellTab
    ) -> AEMotionHostSurfaceAdapter? {
        let role: AEMotionHostSurfaceRole
        switch tab {
        case .home: role = .home
        case .projects: role = .projects
        case .templates: role = .templates
        case .tutorials, .create: return nil
        }

        let key = ObjectIdentifier(controller)
        if let existing = adapters[key], existing.role == role { return existing }
        let created = AEMotionHostSurfaceAdapter(controller: controller, role: role)
        adapters[key] = created
        return created
    }

    private static func homeController(in tabController: UITabBarController) -> UIViewController? {
        guard let index = index(for: .home, in: tabController),
              let controllers = tabController.viewControllers,
              index < controllers.count else { return nil }
        return visibleLeaf(from: controllers[index])
    }

    private static func route(_ tab: HomeShellTab, in tabController: UITabBarController) {
        guard let index = index(for: tab, in: tabController),
              let controllers = tabController.viewControllers,
              index < controllers.count else { return }
        tabController.selectedIndex = index
        tabController.selectedViewController = controllers[index]
        tabController.view.setNeedsLayout()
        tabController.view.layoutIfNeeded()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            scheduleRefreshBurst()
        }
    }

    private static func presentStoryboard(named name: String, from tabController: UITabBarController) {
        guard let destination = UIStoryboard(name: name, bundle: .main).instantiateInitialViewController() else {
            return
        }
        let presenter = visibleLeaf(from: tabController.selectedViewController ?? tabController)
        guard presenter.presentedViewController == nil else { return }
        destination.modalPresentationStyle = .fullScreen
        AEMotionShellViewController.shared.openNonRoot(.detail)
        presenter.present(destination, animated: true) {
            scheduleRefreshBurst()
        }
    }
}
#endif
