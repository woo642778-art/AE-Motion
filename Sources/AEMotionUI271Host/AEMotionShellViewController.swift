#if canImport(UIKit)
import UIKit
import AEMotionExtensionsCore

@MainActor
final class AEMotionShellViewController: UIViewController {
    static let shared = AEMotionShellViewController()

    var routeHandler: ((HomeShellTab) -> Void)?
    var actionHandler: ((AEMotionHomeAction) -> Void)?
    var settingsHandler: (() -> Void)?
    var profileHandler: (() -> Void)?

    private(set) var state = HomeShellState()
    private let headerView = AEMotionShellHeaderView()
    private let contentContainer = UIView()
    private let bottomChromeView = UIView()
    private let navigationView = AEMotionShellNavigationView()
    private let createTray = UIStackView()
    private let passthroughView = AEMotionShellPassthroughView()
    private let homeController = AEMotionHomeViewController()
    private let tutorialController = AEMotionTutorialViewController()
    private var showsHomeContent = true

    private init() {
        super.init(nibName: nil, bundle: nil)
        homeController.actionHandler = { [weak self] action in
            self?.handleHomeAction(action)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = passthroughView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.accessibilityIdentifier = "aemotion.shell.root"

        headerView.translatesAutoresizingMaskIntoConstraints = false
        headerView.onSettings = { [weak self] in self?.settingsHandler?() }
        headerView.onProfile = { [weak self] in self?.profileHandler?() }
        view.addSubview(headerView)

        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.backgroundColor = AEMotionProductTheme.canvas
        view.addSubview(contentContainer)

        bottomChromeView.translatesAutoresizingMaskIntoConstraints = false
        bottomChromeView.backgroundColor = AEMotionProductTheme.canvas
        bottomChromeView.isUserInteractionEnabled = true
        view.addSubview(bottomChromeView)

        navigationView.onSelect = { [weak self] tab in
            self?.handleTabSelection(tab)
        }
        view.addSubview(navigationView)

        configureCreateTray()
        view.addSubview(createTray)

        NSLayoutConstraint.activate([
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.topAnchor.constraint(equalTo: view.topAnchor),
            headerView.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor,
                constant: 72
            ),

            contentContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentContainer.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            bottomChromeView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomChromeView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomChromeView.topAnchor.constraint(equalTo: navigationView.topAnchor, constant: -18),
            bottomChromeView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            navigationView.leadingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.leadingAnchor,
                constant: 12
            ),
            navigationView.trailingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.trailingAnchor,
                constant: -12
            ),
            navigationView.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -6
            ),

            createTray.centerXAnchor.constraint(equalTo: navigationView.centerXAnchor),
            createTray.bottomAnchor.constraint(equalTo: navigationView.topAnchor, constant: -10),
            createTray.widthAnchor.constraint(
                lessThanOrEqualTo: view.safeAreaLayoutGuide.widthAnchor,
                constant: -28
            ),
        ])

        installCustomControllersIfNeeded()
        passthroughView.interactiveRegions = [
            headerView,
            bottomChromeView,
            navigationView,
            createTray,
            contentContainer,
        ]
        updateAppearance(animated: false)
    }

    func configure(tab: HomeShellTab, showsHomeContent: Bool) {
        self.showsHomeContent = showsHomeContent
        if tab != .create {
            HomeShellReducer.reduce(state: &state, event: .selectTab(tab))
        }
        HomeShellReducer.reduce(state: &state, event: .returnToRoot)
        updateAppearance(animated: false)
    }

    func openNonRoot(_ destination: HomeShellDestination) {
        HomeShellReducer.reduce(state: &state, event: .openDestination(destination))
        updateAppearance(animated: true)
    }

    func returnToRoot(tab: HomeShellTab) {
        HomeShellReducer.reduce(state: &state, event: .selectTab(tab))
        HomeShellReducer.reduce(state: &state, event: .returnToRoot)
        updateAppearance(animated: true)
    }

    func prepareForHiddenState() {
        setCreateTrayExpanded(false)
        homeController.view.isHidden = true
        tutorialController.view.isHidden = true
        contentContainer.isHidden = true
        contentContainer.isUserInteractionEnabled = false
        passthroughView.passesThroughContentArea = true
    }

    private func installCustomControllersIfNeeded() {
        install(controller: homeController)
        install(controller: tutorialController)
    }

    private func install(controller: UIViewController) {
        guard controller.parent !== self else { return }
        addChild(controller)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(controller.view)
        NSLayoutConstraint.activate([
            controller.view.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            controller.view.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            controller.view.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
        ])
        controller.didMove(toParent: self)
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
        createTray.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 8,
            leading: 8,
            bottom: 8,
            trailing: 8
        )
        createTray.alpha = 0
        createTray.transform = CGAffineTransform(
            translationX: 0,
            y: 12
        ).scaledBy(x: 0.92, y: 0.92)
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
        HomeShellReducer.reduce(state: &state, event: .returnToRoot)
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
            HomeShellReducer.reduce(
                state: &state,
                event: .openDestination(destination(for: action))
            )
            updateAppearance(animated: true)
            actionHandler?(action)
        }
    }

    private func destination(for action: AEMotionHomeAction) -> HomeShellDestination {
        switch action {
        case .continueEditing, .newProject, .importProject, .camera, .assetLibrary:
            return .editor
        case .threeDStudio, .worldStudio:
            return .detail
        case .precompose, .tracking, .matte, .depthMap, .textTool,
             .speedRemap, .cutout, .presetStudio:
            return .tool
        case .tutorials, .templates:
            return .root
        }
    }

    private func setCreateTrayExpanded(_ expanded: Bool) {
        HomeShellReducer.reduce(
            state: &state,
            event: .setCreateTrayExpanded(expanded)
        )
        if state.isCreateTrayExpanded {
            createTray.isHidden = false
        }
        let changes = { [weak self] in
            guard let self else { return }
            self.createTray.alpha = self.state.isCreateTrayExpanded ? 1 : 0
            self.createTray.transform = self.state.isCreateTrayExpanded
                ? .identity
                : CGAffineTransform(translationX: 0, y: 12).scaledBy(x: 0.92, y: 0.92)
        }
        _ = AEMotionMotionSystem.spring(
            duration: 0.34,
            dampingRatio: 0.82,
            animations: changes
        ) { [weak self] _ in
            guard let self else { return }
            self.createTray.isHidden = !self.state.isCreateTrayExpanded
        }
    }

    private func updateAppearance(animated: Bool) {
        guard isViewLoaded else { return }
        let shouldShowNavigation = state.isRootNavigationVisible
        let shouldShowHome = showsHomeContent
            && state.selectedTab == .home
            && state.destination == .root
        let shouldShowTutorial = state.selectedTab == .tutorials
            && state.destination == .root
        let shouldShowCustomContent = shouldShowHome || shouldShowTutorial

        contentContainer.isHidden = !shouldShowCustomContent
        contentContainer.isUserInteractionEnabled = shouldShowCustomContent
        homeController.view.isHidden = !shouldShowHome
        tutorialController.view.isHidden = !shouldShowTutorial
        passthroughView.passesThroughContentArea = !shouldShowCustomContent
        passthroughView.contentRegion = contentContainer

        headerView.update(tab: state.selectedTab)
        navigationView.setSelectedTab(state.selectedTab, animated: animated)
        headerView.isHidden = !shouldShowNavigation
        bottomChromeView.isHidden = !shouldShowNavigation
        if shouldShowNavigation {
            navigationView.isHidden = false
        }

        let changes = { [weak self] in
            guard let self else { return }
            self.headerView.alpha = shouldShowNavigation ? 1 : 0
            self.bottomChromeView.alpha = shouldShowNavigation ? 1 : 0
            self.navigationView.alpha = shouldShowNavigation ? 1 : 0
            self.navigationView.transform = shouldShowNavigation
                ? .identity
                : CGAffineTransform(translationX: 0, y: 32)
        }
        if animated {
            _ = AEMotionMotionSystem.spring(
                duration: 0.42,
                dampingRatio: 0.84,
                animations: changes
            )
        } else {
            changes()
        }
        navigationView.isUserInteractionEnabled = shouldShowNavigation
        navigationView.isHidden = !shouldShowNavigation && !animated
        if !shouldShowNavigation {
            setCreateTrayExpanded(false)
        }
    }
}

@MainActor
private final class AEMotionShellHeaderView: UIView {
    var onSettings: (() -> Void)?
    var onProfile: (() -> Void)?

    private let subtitleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        accessibilityIdentifier = "aemotion.shell.header"
        backgroundColor = AEMotionProductTheme.canvas
        layer.borderColor = AEMotionProductTheme.separator.cgColor
        layer.borderWidth = 1 / UIScreen.main.scale

        let mark = UILabel()
        mark.text = "Ae"
        mark.font = .systemFont(ofSize: 19, weight: .bold)
        mark.textColor = .white
        mark.textAlignment = .center
        mark.backgroundColor = AEMotionProductTheme.accentPurple
        mark.layer.cornerRadius = 12
        mark.layer.cornerCurve = .continuous
        mark.clipsToBounds = true
        mark.translatesAutoresizingMaskIntoConstraints = false

        let title = UILabel()
        title.text = "AE Motion"
        title.font = .systemFont(ofSize: 24, weight: .bold)
        title.textColor = AEMotionProductTheme.primaryText

        subtitleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        subtitleLabel.textColor = AEMotionProductTheme.secondaryText

        let labels = UIStackView(arrangedSubviews: [title, subtitleLabel])
        labels.axis = .vertical
        labels.spacing = 1

        let settings = makeHeaderButton(
            symbol: "gearshape.fill",
            label: "Settings",
            identifier: "aemotion.shell.settings"
        )
        settings.addAction(UIAction { [weak self] _ in self?.onSettings?() }, for: .touchUpInside)

        let profile = makeHeaderButton(
            symbol: "person.crop.circle.fill",
            label: "Profile",
            identifier: "aemotion.shell.profile"
        )
        profile.addAction(UIAction { [weak self] _ in self?.onProfile?() }, for: .touchUpInside)

        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = UIStackView(arrangedSubviews: [mark, labels, spacer, settings, profile])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        NSLayoutConstraint.activate([
            mark.widthAnchor.constraint(equalToConstant: 46),
            mark.heightAnchor.constraint(equalToConstant: 46),
            settings.widthAnchor.constraint(equalToConstant: 44),
            settings.heightAnchor.constraint(equalToConstant: 44),
            profile.widthAnchor.constraint(equalToConstant: 44),
            profile.heightAnchor.constraint(equalToConstant: 44),
            row.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 18),
            row.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -14),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -13),
        ])
        update(tab: .home)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(tab: HomeShellTab) {
        let section: String
        switch tab {
        case .home: section = "Workspace"
        case .tutorials: section = "Learning Studio"
        case .projects: section = "Projects"
        case .templates: section = "Templates"
        case .create: section = "Create"
        }
        subtitleLabel.text = "\(section) · Build 846"
    }

    private func makeHeaderButton(symbol: String, label: String, identifier: String) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: symbol)
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 21, weight: .semibold)
        configuration.baseForegroundColor = AEMotionProductTheme.primaryText
        configuration.background.backgroundColor = AEMotionProductTheme.elevatedSurface
        configuration.background.cornerRadius = 14
        button.configuration = configuration
        button.accessibilityLabel = label
        button.accessibilityIdentifier = identifier
        return button
    }
}

@MainActor
private final class AEMotionShellPassthroughView: UIView {
    var passesThroughContentArea = false
    weak var contentRegion: UIView?
    var interactiveRegions: [UIView] = []

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        guard passesThroughContentArea else { return hit }
        guard let hit else { return nil }

        if interactiveRegions.contains(where: { region in
            !region.isHidden
                && region.alpha > 0.01
                && (hit === region || hit.isDescendant(of: region))
                && region !== contentRegion
        }) {
            return hit
        }
        return nil
    }
}
#endif
