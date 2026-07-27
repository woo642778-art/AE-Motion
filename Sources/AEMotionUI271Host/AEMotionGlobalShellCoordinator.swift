#if canImport(UIKit)
import UIKit
import AEMotionExtensionsCore

@MainActor
enum AEMotionGlobalShellCoordinator {
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
        for attempt in 0..<80 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(attempt) * 0.15) {
                guard generation == refreshGeneration else { return }
                refreshVisibleShell()
            }
        }
    }

    private static func refreshVisibleShell() {
        guard let window = preferredWindow(),
              let root = window.rootViewController,
              let tabController = findTabController(from: root) else { return }

        let leaf = tabController.selectedViewController.map { visibleLeaf(from: $0) }

        if let leaf, shouldDetachShell(for: leaf, in: tabController) {
            AEMotionShellViewController.shared.detachFromCurrentHost()
            return
        }

        guard let tab = selectedTab(for: tabController, leaf: leaf) else {
            AEMotionShellViewController.shared.detachFromCurrentHost()
            return
        }

        tabController.tabBar.isHidden = true
        tabController.tabBar.isUserInteractionEnabled = false
        tabController.view.backgroundColor = AEMotionProductTheme.canvas
        window.backgroundColor = AEMotionProductTheme.canvas

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
        shell.attach(to: root, tab: tab, showsHomeContent: tab == .home)
        root.view.bringSubviewToFront(shell.view)
    }

    private static func preferredWindow() -> UIWindow? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .filter {
                !$0.isHidden && $0.alpha > 0.01 && $0.windowLevel == .normal && $0.rootViewController != nil
            }
        return windows.first(where: \.isKeyWindow) ?? windows.last
    }

    private static func findTabController(from root: UIViewController) -> UITabBarController? {
        var queue: [UIViewController] = [root]
        var seen = Set<ObjectIdentifier>()
        while !queue.isEmpty {
            let controller = queue.removeFirst()
            guard seen.insert(ObjectIdentifier(controller)).inserted else { continue }
            if let tab = controller as? UITabBarController { return tab }
            queue.append(contentsOf: controller.children)
            if let presented = controller.presentedViewController, !presented.isBeingDismissed {
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
            let name = String(describing: type(of: leaf)).lowercased()
            if name.contains("homevc") || name.contains("homeviewvc") { return .home }
            if name.contains("tutorialvc") || name.contains("learning") { return .tutorials }
            if name.contains("projectsvc") || name.contains("projectslistvc") { return .projects }
            if name.contains("templateslistvc") || name.contains("templatesshowcasevc") { return .templates }
        }

        switch tabController.selectedIndex {
        case 0: return .home
        case 1: return .tutorials
        case 3: return .projects
        case 4: return .templates
        default: return nil
        }
    }

    private static func shouldDetachShell(
        for leaf: UIViewController,
        in tabController: UITabBarController
    ) -> Bool {
        let name = String(describing: type(of: leaf)).lowercased()
        let nonRootMarkers = [
            "projecteditvc", "threedworkspaceviewcontroller",
            "worldworkspaceviewcontroller", "studioscene", "editorviewcontroller",
            "templatepreview", "export", "render"
        ]
        if nonRootMarkers.contains(where: { name.contains($0) }) { return true }

        if let navigation = tabController.selectedViewController as? UINavigationController,
           navigation.viewControllers.count > 1,
           let first = navigation.viewControllers.first {
            let rootName = String(describing: type(of: first)).lowercased()
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
        guard let candidate = tabController.viewControllers?.first else { return nil }
        return visibleLeaf(from: candidate)
    }

    private static func route(_ tab: HomeShellTab, in tabController: UITabBarController) {
        let fallback: Int
        switch tab {
        case .home: fallback = 0
        case .tutorials: fallback = 1
        case .projects: fallback = 3
        case .templates: fallback = 4
        case .create: return
        }
        guard fallback < (tabController.viewControllers?.count ?? 0) else { return }
        tabController.selectedIndex = fallback
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            scheduleRefreshBurst()
        }
    }
}
#endif
