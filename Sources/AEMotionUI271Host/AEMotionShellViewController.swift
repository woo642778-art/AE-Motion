#if canImport(UIKit)
import UIKit
import AEMotionExtensionsCore

@MainActor
final class AEMotionShellViewController: UIViewController {
    static let shared = AEMotionShellViewController()

    var routeHandler: ((HomeShellTab) -> Void)?
    var actionHandler: ((AEMotionHomeAction) -> Void)?

    private(set) var state = HomeShellState()
    private let contentContainer = UIView()
    private let navigationView = AEMotionShellNavigationView()
    private let createTray = UIStackView()
    private let passthroughView = AEMotionShellPassthroughView()
    private let homeController = AEMotionHomeViewController()
    private var navigationBottomConstraint: NSLayoutConstraint?
    private var currentHost: UIViewController?
    private var showsHomeContent = true
    private(set) var rootControllers: [HomeShellTab: UIViewController] = [:]

    private init() {
        super.init(nibName: nil, bundle: nil)
        rootControllers[.home] = homeController
        homeController.actionHandler = { [weak self] action in self?.handleHomeAction(action) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() { view = passthroughView }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.accessibilityIdentifier = "aemotion.shell.root"

        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.backgroundColor = AEMotionProductTheme.canvas
        view.addSubview(contentContainer)

        navigationView.onSelect = { [weak self] tab in self?.handleTabSelection(tab) }
        view.addSubview(navigationView)

        configureCreateTray()
        view.addSubview(createTray)

        navigationBottomConstraint = navigationView.bottomAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.bottomAnchor,
            constant: -6
        )
        NSLayoutConstraint.activate([
            contentContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentContainer.topAnchor.constraint(equalTo: view.topAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            navigationView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            navigationView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            navigationBottomConstraint!,
            createTray.centerXAnchor.constraint(equalTo: navigationView.centerXAnchor),
            createTray.bottomAnchor.constraint(equalTo: navigationView.topAnchor, constant: -10),
            createTray.widthAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.widthAnchor, constant: -28),
        ])
        installHomeControllerIfNeeded()
        updateAppearance(animated: false)
    }

    func attach(to host: UIViewController, tab: HomeShellTab, showsHomeContent: Bool) {
        if parent !== host {
            detachFromCurrentHost()
            host.addChild(self)
            view.translatesAutoresizingMaskIntoConstraints = false
            host.view.addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: host.view.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: host.view.trailingAnchor),
                view.topAnchor.constraint(equalTo: host.view.topAnchor),
                view.bottomAnchor.constraint(equalTo: host.view.bottomAnchor),
            ])
            didMove(toParent: host)
            currentHost = host
        }

        self.showsHomeContent = showsHomeContent
        if tab != .create {
            HomeShellReducer.reduce(state: &state, event: .selectTab(tab))
            rootControllers[tab] = host
        }
        updateAppearance(animated: false)
        host.view.bringSubviewToFront(view)
    }

    func openNonRoot(_ destination: HomeShellDestination) {
        HomeShellReducer.reduce(state: &state, event: .openDestination(destination))
        updateAppearance(animated: true)
    }

    func returnToRoot(tab: HomeShellTab) {
        HomeShellReducer.reduce(state: &state, event: .selectTab(tab))
        updateAppearance(animated: true)
    }

    func detachFromCurrentHost() {
        guard parent != nil else { return }
        willMove(toParent: nil)
        view.removeFromSuperview()
        removeFromParent()
        currentHost = nil
    }

    private func installHomeControllerIfNeeded() {
        guard homeController.parent !== self else { return }
        addChild(homeController)
        homeController.view.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(homeController.view)
        NSLayoutConstraint.activate([
            homeController.view.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            homeController.view.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            homeController.view.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            homeController.view.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
        ])
        homeController.didMove(toParent: self)
    }

    private func configureCreateTray() {
        createTray.translatesAutoresizingMaskIntoConstraints = false
        createTray.axis = .horizontal
        createTray.spacing = 8
        createTray.alignment = .center
        createTray.distribution = .fillEqually
        createTray.backgroundColor = AEMotionProductTheme.elevatedSurface
        createTray.layer.cornerRadius = 20
        createTray.layer.cornerCurve = .continuous
        createTray.layer.borderColor = AEMotionProductTheme.separator.cgColor
        createTray.layer.borderWidth = 1 / UIScreen.main.scale
        createTray.isLayoutMarginsRelativeArrangement = true
        createTray.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
        createTray.alpha = 0
        createTray.transform = CGAffineTransform(translationX: 0, y: 12).scaledBy(x: 0.92, y: 0.92)
        createTray.isHidden = true
        createTray.accessibilityIdentifier = "aemotion.shell.create-tray"

        let actions: [(String, String, AEMotionHomeAction)] = [
            ("New Project", "plus.square.fill", .newProject),
            ("Import", "square.and.arrow.down.fill", .importProject),
            ("Camera", "camera.fill", .camera),
            ("Asset Library", "photo.stack.fill", .assetLibrary),
        ]
        for action in actions {
            let button = UIButton(type: .system)
            var configuration = UIButton.Configuration.tinted()
            configuration.title = action.0
            configuration.image = UIImage(systemName: action.1)
            configuration.imagePlacement = .top
            configuration.imagePadding = 4
            configuration.baseForegroundColor = .white
            configuration.baseBackgroundColor = AEMotionProductTheme.accentPurple.withAlphaComponent(0.15)
            configuration.cornerStyle = .medium
            button.configuration = configuration
            button.accessibilityIdentifier = "aemotion.shell.create.\(action.0.lowercased().replacingOccurrences(of: " ", with: "-"))"
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 62).isActive = true
            button.addAction(UIAction { [weak self] _ in
                self?.setCreateTrayExpanded(false)
                self?.handleHomeAction(action.2)
            }, for: .touchUpInside)
            createTray.addArrangedSubview(button)
        }
    }

    private func handleTabSelection(_ tab: HomeShellTab) {
        if tab == .create {
            setCreateTrayExpanded(!state.isCreateTrayExpanded)
            return
        }
        HomeShellReducer.reduce(state: &state, event: .selectTab(tab))
        updateAppearance(animated: true)
        AEMotionMotionSystem.selectionHaptic()
        routeHandler?(tab)
    }

    private func handleHomeAction(_ action: AEMotionHomeAction) {
        switch action {
        case .tutorials:
            handleTabSelection(.tutorials)
        case .templates:
            handleTabSelection(.templates)
        default:
            HomeShellReducer.reduce(state: &state, event: .openDestination(destination(for: action)))
            updateAppearance(animated: true)
            actionHandler?(action)
        }
    }

    private func destination(for action: AEMotionHomeAction) -> HomeShellDestination {
        switch action {
        case .continueEditing, .newProject, .importProject, .camera, .assetLibrary: return .editor
        case .threeDStudio, .worldStudio: return .detail
        case .speedRemap, .cutout, .depthMap, .presetStudio: return .tool
        case .tutorials, .templates: return .root
        }
    }

    private func setCreateTrayExpanded(_ expanded: Bool) {
        HomeShellReducer.reduce(state: &state, event: .setCreateTrayExpanded(expanded))
        if state.isCreateTrayExpanded { createTray.isHidden = false }
        let changes = { [weak self] in
            guard let self else { return }
            self.createTray.alpha = self.state.isCreateTrayExpanded ? 1 : 0
            self.createTray.transform = self.state.isCreateTrayExpanded
                ? .identity
                : CGAffineTransform(translationX: 0, y: 12).scaledBy(x: 0.92, y: 0.92)
        }
        _ = AEMotionMotionSystem.spring(duration: 0.34, dampingRatio: 0.82, animations: changes) { [weak self] _ in
            guard let self else { return }
            self.createTray.isHidden = !self.state.isCreateTrayExpanded
        }
    }

    private func updateAppearance(animated: Bool) {
        guard isViewLoaded else { return }
        let shouldShowNavigation = state.isRootNavigationVisible
        let shouldShowHome = showsHomeContent && state.selectedTab == .home && state.destination == .root
        passthroughView.passthroughOutsideNavigation = !shouldShowHome
        contentContainer.isHidden = !shouldShowHome
        contentContainer.isUserInteractionEnabled = shouldShowHome
        navigationView.setSelectedTab(state.selectedTab, animated: animated)
        if shouldShowNavigation { navigationView.isHidden = false }

        let changes = { [weak self] in
            guard let self else { return }
            self.navigationView.alpha = shouldShowNavigation ? 1 : 0
            self.navigationView.transform = shouldShowNavigation
                ? .identity
                : CGAffineTransform(translationX: 0, y: 32)
        }
        if animated {
            _ = AEMotionMotionSystem.spring(duration: 0.42, dampingRatio: 0.84, animations: changes)
        } else {
            changes()
        }
        navigationView.isUserInteractionEnabled = shouldShowNavigation
        navigationView.isHidden = !shouldShowNavigation && !animated
        if !shouldShowNavigation { setCreateTrayExpanded(false) }
    }
}

@MainActor
private final class AEMotionShellPassthroughView: UIView {
    var passthroughOutsideNavigation = false

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        guard passthroughOutsideNavigation, hit === self else { return hit }
        return nil
    }
}
#endif
