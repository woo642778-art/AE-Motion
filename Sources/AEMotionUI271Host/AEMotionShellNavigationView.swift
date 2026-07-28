#if canImport(UIKit)
import UIKit
import AEMotionExtensionsCore

@MainActor
final class AEMotionShellNavigationView: UIView {
    var onSelectTab: ((AEMotionRootTab) -> Void)?
    var onToggleCreate: (() -> Void)?

    fileprivate enum Item: Hashable {
        case tab(AEMotionRootTab)
        case create
    }

    private let backgroundView: UIView
    private let selectionCapsule = UIView()
    private let stack = UIStackView()
    private var buttons: [Item: AEMotionShellTabButton] = [:]
    private var capsuleCenterConstraint: NSLayoutConstraint?
    private(set) var selectedTab: AEMotionRootTab = .home

    override init(frame: CGRect) {
        if UIAccessibility.isReduceTransparencyEnabled {
            backgroundView = UIView()
            backgroundView.backgroundColor = AEMotionProductTheme.floatingSurface
        } else {
            backgroundView = UIVisualEffectView(
                effect: UIBlurEffect(style: .systemUltraThinMaterialDark)
            )
        }
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        if UIAccessibility.isReduceTransparencyEnabled {
            backgroundView = UIView()
            backgroundView.backgroundColor = AEMotionProductTheme.floatingSurface
        } else {
            backgroundView = UIVisualEffectView(
                effect: UIBlurEffect(style: .systemUltraThinMaterialDark)
            )
        }
        super.init(coder: coder)
        configure()
    }

    func setSelectedTab(_ tab: AEMotionRootTab, animated: Bool) {
        guard let target = buttons[.tab(tab)] else { return }
        selectedTab = tab
        buttons.forEach { item, button in
            if case .tab(let itemTab) = item {
                button.setSelected(itemTab == tab)
            } else {
                button.setSelected(false)
            }
        }

        capsuleCenterConstraint?.isActive = false
        capsuleCenterConstraint = selectionCapsule.centerXAnchor.constraint(
            equalTo: target.centerXAnchor
        )
        capsuleCenterConstraint?.isActive = true

        let changes = { self.layoutIfNeeded() }
        if animated && !UIAccessibility.isReduceMotionEnabled {
            UIView.animate(
                withDuration: 0.30,
                delay: 0,
                usingSpringWithDamping: 0.82,
                initialSpringVelocity: 0.3,
                options: [.allowUserInteraction, .beginFromCurrentState],
                animations: changes
            )
        } else {
            changes()
        }
    }

    func setCreatePresented(_ presented: Bool) {
        buttons[.create]?.setCreatePresented(presented)
    }

    private func configure() {
        translatesAutoresizingMaskIntoConstraints = false
        accessibilityIdentifier = "aemotion.shell.navigation"
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.32
        layer.shadowRadius = 22
        layer.shadowOffset = CGSize(width: 0, height: 10)

        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.layer.cornerRadius = 27
        backgroundView.layer.cornerCurve = .continuous
        backgroundView.layer.borderColor = UIColor.white.withAlphaComponent(0.10).cgColor
        backgroundView.layer.borderWidth = 1 / UIScreen.main.scale
        backgroundView.clipsToBounds = true
        addSubview(backgroundView)

        selectionCapsule.translatesAutoresizingMaskIntoConstraints = false
        selectionCapsule.backgroundColor = AEMotionProductTheme.accentPurple.withAlphaComponent(0.24)
        selectionCapsule.layer.cornerRadius = 20
        selectionCapsule.layer.cornerCurve = .continuous
        backgroundView.addSubview(selectionCapsule)

        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.alignment = .center
        stack.distribution = .fillEqually
        backgroundView.addSubview(stack)

        let orderedItems: [Item] = [
            .tab(.home),
            .tab(.tutorials),
            .create,
            .tab(.projects),
            .tab(.templates),
        ]
        for item in orderedItems {
            let button = AEMotionShellTabButton(item: item)
            button.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                switch item {
                case .tab(let tab): self.onSelectTab?(tab)
                case .create: self.onToggleCreate?()
                }
            }, for: .touchUpInside)
            buttons[item] = button
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
            selectionCapsule.widthAnchor.constraint(equalToConstant: 58),
            selectionCapsule.heightAnchor.constraint(equalToConstant: 40),
            selectionCapsule.centerYAnchor.constraint(equalTo: backgroundView.centerYAnchor),
        ])

        if let home = buttons[.tab(.home)] {
            capsuleCenterConstraint = selectionCapsule.centerXAnchor.constraint(
                equalTo: home.centerXAnchor
            )
            capsuleCenterConstraint?.isActive = true
        }
        setSelectedTab(.home, animated: false)
    }
}

@MainActor
private final class AEMotionShellTabButton: UIButton {
    private let item: AEMotionShellNavigationView.Item

    init(item: AEMotionShellNavigationView.Item) {
        self.item = item
        super.init(frame: .zero)
        configure()
    }

    required init?(coder: NSCoder) {
        item = .tab(.home)
        super.init(coder: coder)
        configure()
    }

    func setSelected(_ selected: Bool) {
        isSelected = selected
        guard item != .create else { return }
        tintColor = selected
            ? AEMotionProductTheme.primaryText
            : AEMotionProductTheme.tertiaryText
        accessibilityTraits = selected ? [.button, .selected] : .button
    }

    func setCreatePresented(_ presented: Bool) {
        guard item == .create else { return }
        accessibilityTraits = presented ? [.button, .selected] : .button
        layer.shadowOpacity = presented ? 0.65 : 0.38
        transform = presented ? CGAffineTransform(scaleX: 0.94, y: 0.94) : .identity
    }

    private func configure() {
        translatesAutoresizingMaskIntoConstraints = false
        let title = displayTitle
        accessibilityIdentifier = "aemotion.shell.tab.\(identifierComponent)"
        accessibilityLabel = title
        accessibilityHint = item == .create
            ? "Shows or hides project creation options"
            : "Opens \(title)"

        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: iconName)?.applyingSymbolConfiguration(
            AEMotionProductTheme.makeIconConfiguration(
                pointSize: item == .create ? 22 : 18,
                weight: item == .create ? .bold : .semibold
            )
        )
        configuration.imagePlacement = .top
        configuration.imagePadding = 2
        configuration.title = item == .create ? nil : title
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = UIFont.systemFont(ofSize: 9.5, weight: .semibold)
            return outgoing
        }
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: 3,
            leading: 1,
            bottom: 3,
            trailing: 1
        )
        self.configuration = configuration
        tintColor = AEMotionProductTheme.tertiaryText

        if item == .create {
            backgroundColor = AEMotionProductTheme.accentPurple
            layer.cornerRadius = 22
            layer.cornerCurve = .continuous
            layer.shadowColor = AEMotionProductTheme.accentPurple.cgColor
            layer.shadowOpacity = 0.38
            layer.shadowRadius = 12
            layer.shadowOffset = CGSize(width: 0, height: 5)
            widthAnchor.constraint(
                greaterThanOrEqualToConstant: AEMotionProductTheme.minimumTouchTarget
            ).isActive = true
            heightAnchor.constraint(
                equalToConstant: AEMotionProductTheme.minimumTouchTarget
            ).isActive = true
            tintColor = .white
        }
    }

    private var displayTitle: String {
        switch item {
        case .tab(.home): return "Home"
        case .tab(.tutorials): return "Tutorials"
        case .tab(.projects): return "Projects"
        case .tab(.templates): return "Templates"
        case .create: return "Create"
        }
    }

    private var identifierComponent: String {
        switch item {
        case .tab(let tab): return tab.rawValue
        case .create: return "create"
        }
    }

    private var iconName: String {
        switch item {
        case .tab(.home): return "house.fill"
        case .tab(.tutorials): return "play.rectangle.fill"
        case .tab(.projects): return "square.stack.3d.up.fill"
        case .tab(.templates): return "sparkles.rectangle.stack.fill"
        case .create: return "plus"
        }
    }
}
#endif
