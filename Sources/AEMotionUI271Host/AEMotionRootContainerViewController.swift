#if canImport(UIKit)
import UIKit
import AEMotionExtensionsCore

@MainActor
final class AEMotionRootContainerViewController: UIViewController {
    let hostController: UIViewController
    let hostTabController: UITabBarController
    let shellController: AEMotionShellViewController

    private(set) var routeState: AEMotionRouteState
    private lazy var actionRouter = AEMotionActionRouter(
        hostRootController: hostController,
        hostTabController: hostTabController
    )
    private lazy var modalCoordinator = AEMotionModalPresentationCoordinator(
        presenter: self
    )
    private var adapters: [AEMotionRootTab: AEMotionHostSurfaceAdapter] = [:]
    private var backgroundObserver: NSObjectProtocol?

    init(
        hostController: UIViewController,
        hostTabController: UITabBarController,
        initialTab: AEMotionRootTab,
        shellController: AEMotionShellViewController = .shared
    ) {
        self.hostController = hostController
        self.hostTabController = hostTabController
        self.shellController = shellController
        routeState = AEMotionRouteState(selectedTab: initialTab)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let backgroundObserver {
            NotificationCenter.default.removeObserver(backgroundObserver)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AEMotionProductTheme.canvas
        embedHostController()
        embedShellController()
        configureShellCallbacks()
        configureApplicationLifecycle()
        hostTabController.tabBar.isHidden = true
        hostTabController.tabBar.isUserInteractionEnabled = false
        applyRoute(animated: false)
    }

    override var childForStatusBarStyle: UIViewController? {
        presentedViewController ?? hostController
    }

    override var childForStatusBarHidden: UIViewController? {
        presentedViewController ?? hostController
    }

    override var childForHomeIndicatorAutoHidden: UIViewController? {
        presentedViewController ?? hostController
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        presentedViewController?.supportedInterfaceOrientations
            ?? hostController.supportedInterfaceOrientations
    }

    override var shouldAutorotate: Bool {
        presentedViewController?.shouldAutorotate
            ?? hostController.shouldAutorotate
    }

    func selectRootTab(_ tab: AEMotionRootTab, animated: Bool) {
        AEMotionRouteReducer.reduce(
            state: &routeState,
            event: .selectTab(tab)
        )
        applyRoute(animated: animated)
    }

    func dismissCreateTray(animated: Bool) {
        AEMotionRouteReducer.reduce(
            state: &routeState,
            event: .dismissCreateTray
        )
        applyRoute(animated: animated)
    }

    private func configureShellCallbacks() {
        shellController.onSelectTab = { [weak self] tab in
            self?.selectRootTab(tab, animated: true)
        }
        shellController.onToggleCreate = { [weak self] in
            guard let self else { return }
            AEMotionRouteReducer.reduce(
                state: &routeState,
                event: .toggleCreateTray
            )
            applyRoute(animated: true)
        }
        shellController.onDismissCreate = { [weak self] in
            self?.dismissCreateTray(animated: true)
        }
        shellController.onAction = { [weak self] action in
            self?.perform(action)
        }
        shellController.onSettings = { [weak self] in
            self?.presentSettings()
        }
        shellController.onAccount = { [weak self] in
            self?.presentAccount()
        }
    }

    private func configureApplicationLifecycle() {
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                AEMotionRouteReducer.reduce(
                    state: &routeState,
                    event: .applicationDidEnterBackground
                )
                applyRoute(animated: false)
            }
        }
    }

    private func perform(_ action: AEMotionHomeAction) {
        switch action {
        case .tutorials:
            selectRootTab(.tutorials, animated: true)
            return
        case .templates:
            selectRootTab(.templates, animated: true)
            return
        default:
            break
        }

        dismissCreateTray(animated: true)
        actionRouter.perform(
            action,
            from: self,
            completion: { [weak self] result in
                self?.handleActionResult(result)
            },
            onDismiss: { [weak self] in
                self?.returnFromNonRoot()
            }
        )
    }

    private func handleActionResult(_ result: AEMotionActionResult) {
        switch result {
        case .opened(let route):
            AEMotionRouteReducer.reduce(
                state: &routeState,
                event: .confirmNonRoot(route)
            )
            applyRoute(animated: true)

        case .requiresOpenProject:
            AEMotionRouteReducer.reduce(
                state: &routeState,
                event: .routeFailed
            )
            showAlert(
                title: "Open a project first",
                message: "Open an existing project, then choose the tool again."
            )

        case .unavailable(let reason):
            AEMotionRouteReducer.reduce(
                state: &routeState,
                event: .routeFailed
            )
            showAlert(title: "Unavailable", message: reason)

        case .failed(let reason):
            AEMotionRouteReducer.reduce(
                state: &routeState,
                event: .routeFailed
            )
            showAlert(title: "Could not open", message: reason)
        }
    }

    private func returnFromNonRoot() {
        AEMotionRouteReducer.reduce(
            state: &routeState,
            event: .returnToRoot(routeState.selectedTab)
        )
        applyRoute(animated: false)
    }

    private func presentSettings() {
        dismissCreateTray(animated: false)
        modalCoordinator.presentSettings(
            completion: { [weak self] didPresent in
                guard let self else { return }
                if didPresent {
                    AEMotionRouteReducer.reduce(
                        state: &routeState,
                        event: .presentModal(.settings)
                    )
                    applyRoute(animated: false)
                } else {
                    showAlert(
                        title: "Settings unavailable",
                        message: "The Settings screen could not be loaded."
                    )
                }
            },
            onDismiss: { [weak self] in
                self?.modalDidDismiss()
            }
        )
    }

    private func presentAccount() {
        dismissCreateTray(animated: false)
        modalCoordinator.presentAccount(
            completion: { [weak self] didPresent in
                guard let self else { return }
                if didPresent {
                    AEMotionRouteReducer.reduce(
                        state: &routeState,
                        event: .presentModal(.account)
                    )
                    applyRoute(animated: false)
                } else {
                    showAlert(
                        title: "Account unavailable",
                        message: "The Account screen could not be loaded."
                    )
                }
            },
            onDismiss: { [weak self] in
                self?.modalDidDismiss()
            }
        )
    }

    private func modalDidDismiss() {
        AEMotionRouteReducer.reduce(
            state: &routeState,
            event: .dismissModal
        )
        applyRoute(animated: false)
    }

    private func applyRoute(animated: Bool) {
        hostTabController.tabBar.isHidden = true
        hostTabController.tabBar.isUserInteractionEnabled = false
        selectHostTab(routeState.selectedTab)

        let hostContentActive = routeState.nonRoot == nil
            && (routeState.selectedTab == .projects
                || routeState.selectedTab == .templates)
        hostController.view.isUserInteractionEnabled = hostContentActive

        if hostContentActive {
            prepareHostSurface(for: routeState.selectedTab)
        }

        if routeState.nonRoot == nil {
            shellController.restoreFromHiddenState(state: routeState)
        } else {
            shellController.prepareForHiddenState()
        }
    }

    private func selectHostTab(_ tab: AEMotionRootTab) {
        guard let index = hostTabIndex(for: tab),
              let controllers = hostTabController.viewControllers,
              controllers.indices.contains(index) else { return }
        if hostTabController.selectedIndex != index {
            hostTabController.selectedIndex = index
            hostTabController.selectedViewController = controllers[index]
        }
    }

    private func hostTabIndex(for tab: AEMotionRootTab) -> Int? {
        guard let controllers = hostTabController.viewControllers else { return nil }
        let markers: [String]
        switch tab {
        case .home: markers = ["homevc", "homeviewvc"]
        case .tutorials: markers = ["tutorialsviewvc", "tutorialvc", "learning"]
        case .projects: markers = ["projectslistvc", "projectsvc"]
        case .templates: markers = ["templateslistvc", "templatesshowcasevc", "templatesvc"]
        }

        if let index = controllers.firstIndex(where: {
            containsControllerMarker($0, markers: markers)
        }) {
            return index
        }

        guard controllers.count == 4 else { return nil }
        switch tab {
        case .home: return 0
        case .tutorials: return 1
        case .projects: return 2
        case .templates: return 3
        }
    }

    private func containsControllerMarker(
        _ controller: UIViewController,
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

    private func prepareHostSurface(for tab: AEMotionRootTab) {
        guard tab == .projects || tab == .templates,
              let selected = hostTabController.selectedViewController else { return }
        let leaf = visibleLeaf(from: selected)
        if let existing = adapters[tab] {
            existing.refreshForRootPresentation()
            return
        }
        let role: AEMotionHostSurfaceRole = tab == .projects
            ? .projects
            : .templates
        let adapter = AEMotionHostSurfaceAdapter(
            controller: leaf,
            role: role
        )
        adapters[tab] = adapter
        adapter.refreshForRootPresentation()
    }

    private func visibleLeaf(from controller: UIViewController) -> UIViewController {
        if let navigation = controller as? UINavigationController,
           let visible = navigation.visibleViewController {
            return visibleLeaf(from: visible)
        }
        if let tab = controller as? UITabBarController,
           let selected = tab.selectedViewController {
            return visibleLeaf(from: selected)
        }
        return controller
    }

    private func showAlert(title: String, message: String) {
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(
            title: title,
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func embedHostController() {
        guard hostController.parent !== self else { return }
        addChild(hostController)
        hostController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostController.view)
        NSLayoutConstraint.activate([
            hostController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        hostController.didMove(toParent: self)
    }

    private func embedShellController() {
        guard shellController.parent !== self else { return }
        addChild(shellController)
        shellController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(shellController.view)
        NSLayoutConstraint.activate([
            shellController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            shellController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            shellController.view.topAnchor.constraint(equalTo: view.topAnchor),
            shellController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        shellController.didMove(toParent: self)
        view.bringSubviewToFront(shellController.view)
    }
}
#endif
