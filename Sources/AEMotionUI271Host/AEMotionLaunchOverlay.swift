#if canImport(UIKit)
import UIKit

@MainActor
enum AEMotionLaunchOverlay {
    private static let channelURL = URL(string: "https://t.me/aemotionios")!
    private static let channelDismissedKey = "aemotion.build848.official-channel-dismissed"
    private static let presentationDelay: TimeInterval = 0.30
    private static let maximumPresentationAttempts = 40

    private static var hasInstalled = false
    private static var isPresentationScheduled = false
    private static var isPresented = false
    private static var isCompleted = false
    private static weak var overlayView: AEMotionOfficialChannelOverlayView?

    static func install() {
        hasInstalled = true
    }

    static func markShellReady() {
        guard hasInstalled,
              !isCompleted,
              !isPresented,
              !isPresentationScheduled else { return }

        if UserDefaults.standard.bool(forKey: channelDismissedKey) {
            isCompleted = true
            return
        }

        isPresentationScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + presentationDelay) {
            presentInExistingApplicationWindow(attempt: 0)
        }
    }

    private static func presentInExistingApplicationWindow(attempt: Int) {
        guard hasInstalled, !isCompleted, !isPresented else { return }

        guard let window = preferredExistingApplicationWindow() else {
            guard attempt < maximumPresentationAttempts else {
                isPresentationScheduled = false
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
                presentInExistingApplicationWindow(attempt: attempt + 1)
            }
            return
        }

        let overlay = AEMotionOfficialChannelOverlayView()
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.onJoinChannel = {
            UIApplication.shared.open(channelURL, options: [:], completionHandler: nil)
        }
        overlay.onContinue = {
            UserDefaults.standard.set(true, forKey: channelDismissedKey)
            dismiss(animated: true)
        }

        window.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.leadingAnchor.constraint(equalTo: window.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: window.trailingAnchor),
            overlay.topAnchor.constraint(equalTo: window.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: window.bottomAnchor),
        ])
        window.bringSubviewToFront(overlay)

        overlayView = overlay
        isPresentationScheduled = false
        isPresented = true
        overlay.present(animated: true)
    }

    private static func preferredExistingApplicationWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter {
                $0.activationState == .foregroundActive
                    || $0.activationState == .foregroundInactive
            }
            .flatMap(\.windows)
            .filter {
                !$0.isHidden
                    && $0.alpha > 0.01
                    && $0.windowLevel == .normal
                    && $0.rootViewController != nil
                    && !$0.bounds.isEmpty
            }
            .max { left, right in
                if left.isKeyWindow != right.isKeyWindow {
                    return !left.isKeyWindow && right.isKeyWindow
                }
                let leftArea = left.bounds.width * left.bounds.height
                let rightArea = right.bounds.width * right.bounds.height
                return leftArea < rightArea
            }
    }

    private static func dismiss(animated: Bool) {
        guard !isCompleted else { return }
        isCompleted = true
        isPresented = false
        isPresentationScheduled = false

        guard let overlay = overlayView else { return }
        overlay.dismiss(animated: animated) {
            overlay.removeFromSuperview()
        }
        overlayView = nil
    }
}

@MainActor
private final class AEMotionOfficialChannelOverlayView: UIView {
    var onJoinChannel: (() -> Void)?
    var onContinue: (() -> Void)?

    private let dimView = UIView()
    private let cardView = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        accessibilityIdentifier = "aemotion.official-channel.overlay"
        accessibilityViewIsModal = true
        configureHierarchy()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        accessibilityIdentifier = "aemotion.official-channel.overlay"
        accessibilityViewIsModal = true
        configureHierarchy()
    }

    func present(animated: Bool) {
        guard animated, !UIAccessibility.isReduceMotionEnabled else {
            alpha = 1
            cardView.transform = .identity
            return
        }

        alpha = 0
        cardView.transform = CGAffineTransform(translationX: 0, y: 22)
            .scaledBy(x: 0.96, y: 0.96)
        UIView.animate(
            withDuration: 0.32,
            delay: 0,
            usingSpringWithDamping: 0.86,
            initialSpringVelocity: 0.4,
            options: [.allowUserInteraction, .beginFromCurrentState]
        ) {
            self.alpha = 1
            self.cardView.transform = .identity
        }
    }

    func dismiss(animated: Bool, completion: @escaping () -> Void) {
        guard animated, !UIAccessibility.isReduceMotionEnabled else {
            completion()
            return
        }

        UIView.animate(
            withDuration: 0.22,
            delay: 0,
            options: [.curveEaseIn, .beginFromCurrentState]
        ) {
            self.alpha = 0
            self.cardView.transform = CGAffineTransform(translationX: 0, y: 12)
                .scaledBy(x: 0.98, y: 0.98)
        } completion: { _ in
            completion()
        }
    }

    private func configureHierarchy() {
        backgroundColor = .clear

        dimView.translatesAutoresizingMaskIntoConstraints = false
        dimView.backgroundColor = UIColor.black.withAlphaComponent(
            UIAccessibility.isReduceTransparencyEnabled ? 0.96 : 0.78
        )
        addSubview(dimView)

        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.backgroundColor = UIColor(red: 0.055, green: 0.050, blue: 0.080, alpha: 1)
        cardView.layer.cornerRadius = 28
        cardView.layer.cornerCurve = .continuous
        cardView.layer.borderWidth = 1
        cardView.layer.borderColor = UIColor.white.withAlphaComponent(0.12).cgColor
        cardView.layer.shadowColor = UIColor.black.cgColor
        cardView.layer.shadowOpacity = 0.42
        cardView.layer.shadowRadius = 26
        cardView.layer.shadowOffset = CGSize(width: 0, height: 16)
        addSubview(cardView)

        let mark = UILabel()
        mark.translatesAutoresizingMaskIntoConstraints = false
        mark.text = "Ae"
        mark.textColor = .white
        mark.textAlignment = .center
        mark.font = .systemFont(ofSize: 29, weight: .bold)
        mark.backgroundColor = UIColor(red: 0.45, green: 0.20, blue: 0.98, alpha: 1)
        mark.layer.cornerRadius = 19
        mark.layer.cornerCurve = .continuous
        mark.clipsToBounds = true

        let title = makeLabel("AE Motion iOS", size: 29, weight: .bold, color: .white)
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
            self?.onJoinChannel?()
        }, for: .touchUpInside)

        let continueButton = makeButton(
            title: "Continue to AE Motion",
            backgroundColor: UIColor(red: 0.45, green: 0.20, blue: 0.98, alpha: 1)
        )
        continueButton.accessibilityIdentifier = "aemotion.official-channel.continue"
        continueButton.addAction(UIAction { [weak self] _ in
            self?.onContinue?()
        }, for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [
            mark,
            title,
            subtitle,
            message,
            join,
            continueButton,
        ])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 14
        stack.setCustomSpacing(22, after: message)
        cardView.addSubview(stack)

        NSLayoutConstraint.activate([
            dimView.leadingAnchor.constraint(equalTo: leadingAnchor),
            dimView.trailingAnchor.constraint(equalTo: trailingAnchor),
            dimView.topAnchor.constraint(equalTo: topAnchor),
            dimView.bottomAnchor.constraint(equalTo: bottomAnchor),

            cardView.leadingAnchor.constraint(
                greaterThanOrEqualTo: safeAreaLayoutGuide.leadingAnchor,
                constant: 22
            ),
            cardView.trailingAnchor.constraint(
                lessThanOrEqualTo: safeAreaLayoutGuide.trailingAnchor,
                constant: -22
            ),
            cardView.centerXAnchor.constraint(equalTo: centerXAnchor),
            cardView.centerYAnchor.constraint(equalTo: centerYAnchor),
            cardView.widthAnchor.constraint(lessThanOrEqualToConstant: 430),

            stack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 26),
            stack.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -24),

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
        return label
    }

    private func makeButton(title: String, backgroundColor: UIColor) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 17, weight: .bold)
        button.backgroundColor = backgroundColor
        button.layer.cornerRadius = 16
        button.layer.cornerCurve = .continuous
        return button
    }
}
#endif
