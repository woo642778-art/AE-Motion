#if canImport(UIKit)
import UIKit
import AEMotionExtensionsCore

@MainActor
final class AEMotionShellViewController: UIViewController {
    static let shared = AEMotionShellViewController()

    var onSelectTab: ((AEMotionRootTab) -> Void)?
    var onToggleCreate: (() -> Void)?
    var onDismissCreate: (() -> Void)?
    var onAction: ((AEMotionHomeAction) -> Void)?
    var onSettings: (() -> Void)?
    var onAccount: (() -> Void)?

    private let rootView = AEMotionShellRootView()
    private let headerView = AEMotionShellHeaderView()
    private let contentController = AEMotionShellContentController()
    private let createTrayController = AEMotionCreateTrayController()
    private let bottomChromeView = UIView()
    private let navigationView = AEMotionShellNavigationView()

    private(set) var renderedState = AEMotionRouteState()

    private init() {
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = rootView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.accessibilityIdentifier = "aemotion.shell.root"

        configureHeader()
        embedContentController()
        configureBottomChrome()
        configureNavigation()
        embedCreateTrayController()

        rootView.headerView = headerView
        rootView.navigationView = navigationView
        rootView.bottomChromeView = bottomChromeView
        rootView.contentView = contentController.view
        rootView.createTrayView = createTrayController.view

        render(state: renderedState, animated: false)
    }

    func render(state: AEMotionRouteState, animated: Bool) {
        loadViewIfNeeded()
        renderedState = state

        headerView.update(tab: state.selectedTab)
        navigationView.setSelectedTab(state.selectedTab, animated: animated)
        navigationView.setCreatePresented(state.isCreateTrayPresented)
        contentController.show(tab: state.selectedTab)
        createTrayController.setPresented(
            state.isCreateTrayPresented,
            animated: animated
        )

        let rootChromeVisible = state.isRootChromeVisible
        headerView.isHidden = !rootChromeVisible
        bottomChromeView.isHidden = !rootChromeVisible
        navigationView.isHidden = !rootChromeVisible
        headerView.isUserInteractionEnabled = rootChromeVisible
        bottomChromeView.isUserInteractionEnabled = rootChromeVisible
        navigationView.isUserInteractionEnabled = rootChromeVisible

        let sourceContentVisible = rootChromeVisible
            && (state.selectedTab == .home || state.selectedTab == .tutorials)
        contentController.view.isHidden = !sourceContentVisible
        contentController.view.isUserInteractionEnabled = sourceContentVisible
        rootView.passesHostContentTouches = rootChromeVisible && !sourceContentVisible

        if !rootChromeVisible {
            createTrayController.setPresented(false, animated: false)
            contentController.prepareForHiddenState()
        }
    }

    func prepareForHiddenState() {
        loadViewIfNeeded()
        createTrayController.setPresented(false, animated: false)
        contentController.prepareForHiddenState()
        view.isUserInteractionEnabled = false
        view.isHidden = true
    }

    func restoreFromHiddenState(state: AEMotionRouteState) {
        loadViewIfNeeded()
        view.isHidden = false
        view.isUserInteractionEnabled = true
        render(state: state, animated: false)
    }

    private func configureHeader() {
        headerView.translatesAutoresizingMaskIntoConstraints = false
        headerView.onSettings = { [weak self] in self?.onSettings?() }
        headerView.onAccount = { [weak self] in self?.onAccount?() }
        view.addSubview(headerView)

        NSLayoutConstraint.activate([
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.topAnchor.constraint(equalTo: view.topAnchor),
            headerView.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor,
                constant: 72
            ),
        ])
    }

    private func embedContentController() {
        addChild(contentController)
        contentController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentController.view)
        NSLayoutConstraint.activate([
            contentController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentController.view.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            contentController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        contentController.didMove(toParent: self)
        contentController.onHomeAction = { [weak self] action in
            self?.onAction?(action)
        }
    }

    private func configureBottomChrome() {
        bottomChromeView.translatesAutoresizingMaskIntoConstraints = false
        bottomChromeView.backgroundColor = AEMotionProductTheme.canvas
        bottomChromeView.isUserInteractionEnabled = false
        view.addSubview(bottomChromeView)
    }

    private func configureNavigation() {
        navigationView.onSelectTab = { [weak self] tab in
            self?.onSelectTab?(tab)
        }
        navigationView.onToggleCreate = { [weak self] in
            self?.onToggleCreate?()
        }
        view.addSubview(navigationView)

        NSLayoutConstraint.activate([
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

            bottomChromeView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomChromeView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomChromeView.topAnchor.constraint(
                equalTo: navigationView.topAnchor,
                constant: -18
            ),
            bottomChromeView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func embedCreateTrayController() {
        addChild(createTrayController)
        createTrayController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(createTrayController.view)
        NSLayoutConstraint.activate([
            createTrayController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            createTrayController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            createTrayController.view.topAnchor.constraint(equalTo: view.topAnchor),
            createTrayController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        createTrayController.didMove(toParent: self)
        createTrayController.onDismiss = { [weak self] in
            self?.onDismissCreate?()
        }
        createTrayController.onAction = { [weak self] action in
            self?.onAction?(action)
        }

        view.bringSubviewToFront(bottomChromeView)
        view.bringSubviewToFront(navigationView)
    }
}

@MainActor
private final class AEMotionShellRootView: UIView {
    weak var headerView: UIView?
    weak var navigationView: UIView?
    weak var bottomChromeView: UIView?
    weak var contentView: UIView?
    weak var createTrayView: UIView?
    var passesHostContentTouches = false

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, alpha > 0.01, isUserInteractionEnabled else {
            return nil
        }

        let hit = super.hitTest(point, with: event)
        guard let hit else { return nil }
        if hit === self { return nil }

        if let createTrayView,
           !createTrayView.isHidden,
           createTrayView.alpha > 0.01,
           (hit === createTrayView || hit.isDescendant(of: createTrayView)) {
            return hit
        }

        for ownedRegion in [headerView, navigationView, bottomChromeView].compactMap({ $0 }) {
            if !ownedRegion.isHidden,
               ownedRegion.alpha > 0.01,
               (hit === ownedRegion || hit.isDescendant(of: ownedRegion)) {
                return hit
            }
        }

        if passesHostContentTouches,
           let contentView,
           (hit === contentView || hit.isDescendant(of: contentView)) {
            return nil
        }
        return hit
    }
}

@MainActor
private final class AEMotionShellHeaderView: UIView {
    var onSettings: (() -> Void)?
    var onAccount: (() -> Void)?

    private let subtitleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureHierarchy()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureHierarchy()
    }

    func update(tab: AEMotionRootTab) {
        let section: String
        switch tab {
        case .home: section = "Workspace"
        case .tutorials: section = "Learning Studio"
        case .projects: section = "Projects"
        case .templates: section = "Templates"
        }
        subtitleLabel.text = "\(section) · Build \(AEMotionRelease.buildNumber)"
    }

    private func configureHierarchy() {
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
        settings.addAction(UIAction { [weak self] _ in
            self?.onSettings?()
        }, for: .touchUpInside)

        let account = makeHeaderButton(
            symbol: "person.crop.circle.fill",
            label: "Account",
            identifier: "aemotion.shell.account"
        )
        account.addAction(UIAction { [weak self] _ in
            self?.onAccount?()
        }, for: .touchUpInside)

        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [mark, labels, spacer, settings, account])
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
            account.widthAnchor.constraint(equalToConstant: 44),
            account.heightAnchor.constraint(equalToConstant: 44),
            row.leadingAnchor.constraint(
                equalTo: safeAreaLayoutGuide.leadingAnchor,
                constant: 18
            ),
            row.trailingAnchor.constraint(
                equalTo: safeAreaLayoutGuide.trailingAnchor,
                constant: -14
            ),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -13),
        ])
        update(tab: .home)
    }

    private func makeHeaderButton(
        symbol: String,
        label: String,
        identifier: String
    ) -> UIButton {
        let button = UIButton(type: .system)
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: symbol)
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
            pointSize: 21,
            weight: .semibold
        )
        configuration.baseForegroundColor = AEMotionProductTheme.primaryText
        configuration.background.backgroundColor = AEMotionProductTheme.elevatedSurface
        configuration.background.cornerRadius = 14
        button.configuration = configuration
        button.accessibilityLabel = label
        button.accessibilityIdentifier = identifier
        return button
    }
}
#endif
