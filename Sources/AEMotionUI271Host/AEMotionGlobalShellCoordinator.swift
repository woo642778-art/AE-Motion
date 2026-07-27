#if canImport(UIKit)
import UIKit
import AEMotionExtensionsCore

@MainActor
enum AEMotionGlobalShellCoordinator {
    private struct WindowCandidate {
        let window: UIWindow
        let hostRoot: UIViewController
        let tabController: UITabBarController
        let area: CGFloat
    }

    private static let controllerMarkers: [HomeShellTab: [String]] = [
        .home: ["homevc", "homeviewvc"],
        .tutorials: ["tutorialsviewvc", "tutorialvc", "learning"],
        .projects: ["projectslistvc", "projectsvc"],
        .templates: ["templateslistvc", "templatesshowcasevc", "templatesvc"],
    ]

    private static var hasStarted = false
    private static var observers: [NSObjectProtocol] = []
    private static var refreshGeneration = 0
    private static var adapters: [ObjectIdentifier: AEMotionHostSurfaceAdapter] = [:]

    static func start() {
        guard !hasStarted else {
            scheduleRefreshBurst()
            return
        }
        hasStarted = true

        let center = NotificationCenter.default
        for name in [
            UIApplication.didFinishLaunchingNotification,
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
        scheduleRefreshBurst()
    }

    private static func scheduleRefreshBurst() {
        refreshGeneration += 1
        let generation = refreshGeneration
        for attempt in 0..<160 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(attempt) * 0.10) {
                guard generation == refreshGeneration else { return }
                refreshVisibleShell()
            }
        }
    }

    private static func refreshVisibleShell() {
        guard let candidate = preferredCandidate(), isSafeToWrap(candidate) else { return }
        let container = ensureRootContainer(
            for: candidate.window,
            hostRoot: candidate.hostRoot
        )
        let tabController = candidate.tabController
        let leaf = tabController.selectedViewController.map { visibleLeaf(from: $0) }

        if let leaf, shouldDetachShell(for: leaf, in: tabController) {
            container.hideShell()
            return
        }

        guard let tab = selectedTab(for: tabController, leaf: leaf) else {
            container.hideShell()
            return
        }

        tabController.tabBar.isHidden = true
        tabController.tabBar.isUserInteractionEnabled = false
        tabController.view.backgroundColor = AEMotionProductTheme.canvas
        candidate.window.backgroundColor = AEMotionProductTheme.canvas

        let activeAdapter = leaf.flatMap { adapter(for: $0, tab: tab) }
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
        container.showShell(tab: tab, showsHomeContent: tab == .home)
        AEMotionLaunchOverlay.markShellReady()
    }

    private static func isSafeToWrap(_ candidate: WindowCandidate) -> Bool {
        if candidate.window.rootViewController is AEMotionRootContainerViewController {
            return true
        }
        return candidate.hostRoot.presentedViewController == nil
            && !candidate.hostRoot.isBeingPresented
            && !candidate.hostRoot.isBeingDismissed
            && !hasBlockingLaunchOverlay(
                in: candidate.window,
                hostRoot: candidate.hostRoot
            )
    }

    private static func hasBlockingLaunchOverlay(
        in window: UIWindow,
        hostRoot: UIViewController
    ) -> Bool {
        guard hostRoot.isViewLoaded else { return false }
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
            let coverage: CGFloat
            if visibleFrame.isNull || visibleFrame.isEmpty {
                coverage = 0
            } else {
                coverage = (visibleFrame.width * visibleFrame.height) / windowArea
            }
            if coverage >= 0.55 { return true }
            return view.subviews.contains(where: containsBlockingOverlay)
        }

        return window.subviews.contains(where: containsBlockingOverlay)
    }

    private static func preferredCandidate() -> WindowCandidate? {
        let candidates: [WindowCandidate] = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .compactMap { window in
                guard !window.isHidden,
                      window.alpha > 0.01,
                      window.windowLevel == .normal,
                      let root = window.rootViewController else { return nil }
                let hostRoot = (root as? AEMotionRootContainerViewController)?.hostController ?? root
                guard let tabController = findTabController(from: hostRoot) else { return nil }
                let area = window.bounds.width * window.bounds.height
                return WindowCandidate(
                    window: window,
                    hostRoot: hostRoot,
                    tabController: tabController,
                    area: area
                )
            }

        return candidates.max { left, right in
            if left.area == right.area {
                return !left.window.isKeyWindow && right.window.isKeyWindow
            }
            return left.area < right.area
        }
    }

    private static func ensureRootContainer(
        for window: UIWindow,
        hostRoot: UIViewController
    ) -> AEMotionRootContainerViewController {
        if let existing = window.rootViewController as? AEMotionRootContainerViewController {
            return existing
        }
        let container = AEMotionRootContainerViewController(hostController: hostRoot)
        window.rootViewController = container
        container.loadViewIfNeeded()
        return container
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

    private static func selectedTab(
        for tabController: UITabBarController,
        leaf: UIViewController?
    ) -> HomeShellTab? {
        if let leaf {
            for tab in [HomeShellTab.home, .tutorials, .projects, .templates] {
                guard let markers = controllerMarkers[tab] else { continue }
                if matches(controller: leaf, markers: markers) { return tab }
            }
        }

        for tab in [HomeShellTab.home, .tutorials, .projects, .templates] {
            if index(for: tab, in: tabController) == tabController.selectedIndex {
                return tab
            }
        }
        return nil
    }

    private static func index(for tab: HomeShellTab, in tabController: UITabBarController) -> Int? {
        guard tab != .create,
              let controllers = tabController.viewControllers,
              let markers = controllerMarkers[tab] else { return nil }

        if let exact = controllers.firstIndex(where: { matches(controller: $0, markers: markers) }) {
            return exact
        }

        if controllers.count == 4 {
            switch tab {
            case .home: return 0
            case .tutorials: return 1
            case .projects: return 2
            case .templates: return 3
            case .create: return nil
            }
        }
        if controllers.count >= 5 {
            switch tab {
            case .home: return 0
            case .tutorials: return 1
            case .projects: return 3
            case .templates: return 4
            case .create: return nil
            }
        }
        return nil
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
