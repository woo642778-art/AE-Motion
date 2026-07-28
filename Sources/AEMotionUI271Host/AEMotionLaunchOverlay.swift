#if canImport(UIKit)
import UIKit

@MainActor
enum AEMotionLaunchOverlay {
    static let officialChannelURL = URL(string: "https://t.me/aemotionios")!

    private static let dismissedKey = "aemotion.build851.official-channel-dismissed"
    private static var isPresenting = false

    static func install() {}

    static func markShellReady() {}

    static func presentIfNeeded(
        from presenter: UIViewController,
        completion: @escaping (Bool) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        guard !isPresenting,
              !UserDefaults.standard.bool(forKey: dismissedKey),
              presenter.presentedViewController == nil else {
            completion(false)
            return
        }

        isPresenting = true
        let controller = AEMotionOfficialChannelViewController()
        controller.onJoin = {
            UIApplication.shared.open(
                officialChannelURL,
                options: [:],
                completionHandler: nil
            )
        }
        controller.onContinue = {
            UserDefaults.standard.set(true, forKey: dismissedKey)
            controller.dismiss(animated: true) {
                isPresenting = false
                onDismiss()
            }
        }
        controller.modalPresentationStyle = .overFullScreen
        controller.modalTransitionStyle = .crossDissolve
        presenter.present(controller, animated: true) {
            completion(true)
        }
    }
}

@MainActor
private final class AEMotionOfficialChannelViewController: UIViewController {
    var onJoin: (() -> Void)?
    var onContinue: (() -> Void)?

    private let dimView = UIView()
    private let cardView = UIView()
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.accessibilityIdentifier = "aemotion.official-channel.root"
        view.accessibilityViewIsModal = true
        configureHierarchy()
    }

    private func configureHierarchy() {
        dimView.translatesAutoresizingMaskIntoConstraints = false
        dimView.backgroundColor = UIColor.black.withAlphaComponent(
            UIAccessibility.isReduceTransparencyEnabled ? 0.96 : 0.78
        )
        view.addSubview(dimView)

        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.backgroundColor = UIColor(
            red: 0.055,
            green: 0.050,
            blue: 0.080,
            alpha: 1
        )
        cardView.layer.cornerRadius = 28
        cardView.layer.cornerCurve = .continuous
        cardView.layer.borderWidth = 1
        cardView.layer.borderColor = UIColor.white.withAlphaComponent(0.12).cgColor
        cardView.layer.shadowColor = UIColor.black.cgColor
        cardView.layer.shadowOpacity = 0.42
        cardView.layer.shadowRadius = 26
        cardView.layer.shadowOffset = CGSize(width: 0, height: 16)
        view.addSubview(cardView)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = false
        scrollView.showsVerticalScrollIndicator = true
        cardView.addSubview(scrollView)

        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.alignment = .fill
        contentStack.spacing = 14
        scrollView.addSubview(contentStack)

        let mark = UILabel()
        mark.translatesAutoresizingMaskIntoConstraints = false
        mark.text = "Ae"
        mark.textColor = .white
        mark.textAlignment = .center
        mark.font = .systemFont(ofSize: 29, weight: .bold)
        mark.backgroundColor = AEMotionProductTheme.accentPurple
        mark.layer.cornerRadius = 19
        mark.layer.cornerCurve = .continuous
        mark.clipsToBounds = true

        let title = makeLabel(
            "AE Motion iOS",
            size: 29,
            weight: .bold,
            color: .white
        )
        let subtitle = makeLabel(
            "Official Channel",
            size: 18,
            weight: .semibold,
            color: UIColor(red: 0.70, green: 0.54, blue: 1, alpha: 1)
        )
        let message = makeLabel(
            "Get release notes, update files, and support from the official AE Motion Telegram channel.",
            size: 15,
            weight: .medium,
            color: UIColor(white: 0.74, alpha: 1)
        )
        message.numberOfLines = 0

        let join = makeButton(
            title: "Join AE Motion Telegram",
            backgroundColor: UIColor(red: 0.13, green: 0.58, blue: 0.95, alpha: 1)
        )
        join.accessibilityIdentifier = "aemotion.official-channel.join"
        join.addAction(UIAction { [weak self] _ in
            self?.onJoin?()
        }, for: .touchUpInside)

        let continueButton = makeButton(
            title: "Continue to AE Motion",
            backgroundColor: AEMotionProductTheme.accentPurple
        )
        continueButton.accessibilityIdentifier = "aemotion.official-channel.continue"
        continueButton.addAction(UIAction { [weak self] _ in
            self?.onContinue?()
        }, for: .touchUpInside)

        [mark, title, subtitle, message, join, continueButton]
            .forEach(contentStack.addArrangedSubview)
        contentStack.setCustomSpacing(22, after: message)

        let adaptiveWidth = cardView.widthAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.widthAnchor,
            constant: -40
        )
        adaptiveWidth.priority = UILayoutPriority(999)

        NSLayoutConstraint.activate([
            dimView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dimView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dimView.topAnchor.constraint(equalTo: view.topAnchor),
            dimView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            cardView.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            cardView.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            cardView.leadingAnchor.constraint(
                greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor,
                constant: 20
            ),
            cardView.trailingAnchor.constraint(
                lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor,
                constant: -20
            ),
            cardView.widthAnchor.constraint(lessThanOrEqualToConstant: 430),
            cardView.heightAnchor.constraint(
                lessThanOrEqualTo: view.safeAreaLayoutGuide.heightAnchor,
                constant: -40
            ),
            adaptiveWidth,

            scrollView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: cardView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: cardView.bottomAnchor),

            contentStack.leadingAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.leadingAnchor,
                constant: 24
            ),
            contentStack.trailingAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.trailingAnchor,
                constant: -24
            ),
            contentStack.topAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.topAnchor,
                constant: 26
            ),
            contentStack.bottomAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.bottomAnchor,
                constant: -24
            ),
            contentStack.widthAnchor.constraint(
                equalTo: scrollView.frameLayoutGuide.widthAnchor,
                constant: -48
            ),

            mark.widthAnchor.constraint(equalToConstant: 76),
            mark.heightAnchor.constraint(equalToConstant: 76),
            join.heightAnchor.constraint(equalToConstant: 56),
            continueButton.heightAnchor.constraint(equalToConstant: 56),
        ])

        mark.setContentHuggingPriority(.required, for: .horizontal)
        mark.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    private func makeLabel(
        _ text: String,
        size: CGFloat,
        weight: UIFont.Weight,
        color: UIColor
    ) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.textAlignment = .center
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        return label
    }

    private func makeButton(
        title: String,
        backgroundColor: UIColor
    ) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 17, weight: .bold)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.titleLabel?.numberOfLines = 2
        button.titleLabel?.textAlignment = .center
        button.backgroundColor = backgroundColor
        button.layer.cornerRadius = 16
        button.layer.cornerCurve = .continuous
        return button
    }
}
#endif
