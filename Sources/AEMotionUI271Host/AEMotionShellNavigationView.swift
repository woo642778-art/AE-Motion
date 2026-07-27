#if canImport(UIKit)
import UIKit
import AEMotionExtensionsCore

@MainActor
final class AEMotionShellNavigationView: UIView {
    var onSelect: ((HomeShellTab) -> Void)?

    private let backgroundView: UIView
    private let capsule = UIView()
    private let stack = UIStackView()
    private var buttons: [HomeShellTab: AEMotionShellTabButton] = [:]
    private var capsuleCenterConstraint: NSLayoutConstraint?
    private(set) var selectedTab: HomeShellTab = .home

    override init(frame: CGRect) {
        if UIAccessibility.isReduceTransparencyEnabled {
            backgroundView = UIView()
            backgroundView.backgroundColor = AEMotionProductTheme.floatingSurface
        } else {
            backgroundView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        }
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        if UIAccessibility.isReduceTransparencyEnabled {
            backgroundView = UIView()
            backgroundView.backgroundColor = AEMotionProductTheme.floatingSurface
        } else {
            backgroundView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        }
        super.init(coder: coder)
        configure()
    }

    func setSelectedTab(_ tab: HomeShellTab, animated: Bool) {
        guard tab != .create, let target = buttons[tab] else { return }
        selectedTab = tab
        buttons.forEach { key, button in button.setSelected(key == tab) }
        capsuleCenterConstraint?.isActive = false
        capsuleCenterConstraint = capsule.centerXAnchor.constraint(equalTo: target.centerXAnchor)
        capsuleCenterConstraint?.isActive = true

        let changes: () -> Void = { [weak self] in
            guard let self else { return }
            self.layoutIfNeeded()
        }
        if animated {
            _ = AEMotionMotionSystem.spring(duration: 0.48, dampingRatio: 0.78, animations: changes)
        } else {
            changes()
        }
    }

    private func configure() {
        translatesAutoresizingMaskIntoConstraints = false
        accessibilityIdentifier = "aemotion.shell.navigation"
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.34
        layer.shadowRadius = 24
        layer.shadowOffset = CGSize(width: 0, height: 12)

        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.layer.cornerRadius = 27
        backgroundView.layer.cornerCurve = .continuous
        backgroundView.layer.borderColor = UIColor.white.withAlphaComponent(0.10).cgColor
        backgroundView.layer.borderWidth = 1 / UIScreen.main.scale
        backgroundView.clipsToBounds = true
        addSubview(backgroundView)

        capsule.translatesAutoresizingMaskIntoConstraints = false
        capsule.backgroundColor = AEMotionProductTheme.accentPurple.withAlphaComponent(0.25)
        capsule.layer.cornerRadius = 20
        capsule.layer.cornerCurve = .continuous
        backgroundView.addSubview(capsule)

        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.alignment = .center
        stack.distribution = .fillEqually
        backgroundView.addSubview(stack)

        for tab in HomeShellTab.allCases {
            let button = AEMotionShellTabButton(tab: tab)
            button.addAction(UIAction { [weak self] _ in self?.onSelect?(tab) }, for: .touchUpInside)
            buttons[tab] = button
            stack.addArrangedSubview(button)
        }

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: AEMotionProductTheme.navigationHeight),
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -7),
            stack.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 7),
            stack.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -7),
            stack.topAnchor.constraint(equalTo: backgroundView.topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor, constant: -4),
            capsule.widthAnchor.constraint(equalToConstant: 58),
            capsule.heightAnchor.constraint(equalToConstant: 40),
            capsule.centerYAnchor.constraint(equalTo: backgroundView.centerYAnchor),
        ])

        if let home = buttons[.home] {
            capsuleCenterConstraint = capsule.centerXAnchor.constraint(equalTo: home.centerXAnchor)
            capsuleCenterConstraint?.isActive = true
        }
        setSelectedTab(.home, animated: false)
    }
}

@MainActor
private final class AEMotionShellTabButton: UIButton {
    let tab: HomeShellTab
    private let titleText: String

    init(tab: HomeShellTab) {
        self.tab = tab
        switch tab {
        case .home: titleText = "Home"
        case .tutorials: titleText = "Tutorials"
        case .create: titleText = "Create"
        case .projects: titleText = "Projects"
        case .templates: titleText = "Templates"
        }
        super.init(frame: .zero)
        configure()
    }

    required init?(coder: NSCoder) {
        tab = .home
        titleText = "Home"
        super.init(coder: coder)
        configure()
    }

    func setSelected(_ selected: Bool) {
        isSelected = selected
        tintColor = selected ? AEMotionProductTheme.primaryText : AEMotionProductTheme.tertiaryText
        accessibilityTraits = selected ? [.button, .selected] : .button
    }

    private func configure() {
        translatesAutoresizingMaskIntoConstraints = false
        accessibilityIdentifier = "aemotion.shell.tab.\(tab.rawValue)"
        accessibilityLabel = titleText
        accessibilityHint = tab == .create ? "Shows project creation options" : "Opens \(titleText)"

        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: iconName)?.applyingSymbolConfiguration(
            AEMotionProductTheme.makeIconConfiguration(
                pointSize: tab == .create ? 22 : 18,
                weight: tab == .create ? .bold : .semibold
            )
        )
        configuration.imagePlacement = .top
        configuration.imagePadding = 2
        configuration.title = tab == .create ? nil : titleText
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = UIFont.systemFont(ofSize: 9.5, weight: .semibold)
            return outgoing
        }
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 3, leading: 1, bottom: 3, trailing: 1)
        self.configuration = configuration
        tintColor = AEMotionProductTheme.tertiaryText

        if tab == .create {
            backgroundColor = AEMotionProductTheme.accentPurple
            layer.cornerRadius = 22
            layer.cornerCurve = .continuous
            layer.shadowColor = AEMotionProductTheme.accentPurple.cgColor
            layer.shadowOpacity = 0.42
            layer.shadowRadius = 12
            layer.shadowOffset = CGSize(width: 0, height: 5)
            widthAnchor.constraint(greaterThanOrEqualToConstant: AEMotionProductTheme.minimumTouchTarget).isActive = true
            heightAnchor.constraint(equalToConstant: AEMotionProductTheme.minimumTouchTarget).isActive = true
            tintColor = .white
        }
    }

    private var iconName: String {
        switch tab {
        case .home: return "house.fill"
        case .tutorials: return "play.rectangle.fill"
        case .create: return "plus"
        case .projects: return "square.stack.3d.up.fill"
        case .templates: return "sparkles.rectangle.stack.fill"
        }
    }
}
#endif
