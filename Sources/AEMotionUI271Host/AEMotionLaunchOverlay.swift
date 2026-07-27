#if canImport(UIKit)
import UIKit

@MainActor
enum AEMotionLaunchOverlay {
    static let minimumVisibleDuration: TimeInterval = 1.4
    private static let maximumVisibleDuration: TimeInterval = 6.0
    private static let channelURL = URL(string: "https://t.me/aemotionios")!
    private static let channelDismissedKey = "aemotion.build846.official-channel-dismissed"

    private static var hasStarted = false
    private static var startedAt = Date()
    private static var isShellReady = false
    private static var overlayWindow: UIWindow?
    private static var overlayController: AEMotionLaunchExperienceViewController?
    private static var observers: [NSObjectProtocol] = []
    private static var presentationGeneration = 0

    static func install() {
        guard !hasStarted else {
            schedulePresentationBurst()
            return
        }
        hasStarted = true
        startedAt = Date()

        let center = NotificationCenter.default
        for name in [
            UIApplication.didFinishLaunchingNotification,
            UIApplication.didBecomeActiveNotification,
            UIWindow.didBecomeVisibleNotification,
            UIScene.didActivateNotification,
        ] {
            observers.append(center.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { _ in
                Task { @MainActor in schedulePresentationBurst() }
            })
        }
        schedulePresentationBurst()

        DispatchQueue.main.asyncAfter(deadline: .now() + maximumVisibleDuration) {
            guard !isShellReady else { return }
            dismissOverlay(animated: true)
        }
    }

    static func markShellReady() {
        isShellReady = true
        presentIfPossible()
        let elapsed = Date().timeIntervalSince(startedAt)
        let delay = max(0, minimumVisibleDuration - elapsed)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            finishLoadingPhase()
        }
    }

    private static func schedulePresentationBurst() {
        presentationGeneration += 1
        let generation = presentationGeneration
        for attempt in 0..<100 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(attempt) * 0.05) {
                guard generation == presentationGeneration else { return }
                presentIfPossible()
            }
        }
    }

    private static func presentIfPossible() {
        guard overlayWindow == nil,
              let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive })
        else { return }

        let controller = AEMotionLaunchExperienceViewController()
        controller.onJoinChannel = {
            UIApplication.shared.open(channelURL, options: [:], completionHandler: nil)
        }
        controller.onCloseChannel = {
            UserDefaults.standard.set(true, forKey: channelDismissedKey)
            dismissOverlay(animated: true)
        }

        let window = UIWindow(windowScene: scene)
        window.windowLevel = UIWindow.Level.alert + 100
        window.backgroundColor = UIColor(white: 0.02, alpha: 1)
        window.rootViewController = controller
        window.accessibilityIdentifier = "aemotion.launch.window"
        overlayController = controller
        overlayWindow = window
        window.makeKeyAndVisible()
    }

    private static func finishLoadingPhase() {
        guard isShellReady else { return }
        if UserDefaults.standard.bool(forKey: channelDismissedKey) {
            dismissOverlay(animated: true)
        } else {
            overlayController?.showOfficialChannel()
        }
    }

    private static func dismissOverlay(animated: Bool) {
        guard let window = overlayWindow else { return }
        let finish = {
            window.isHidden = true
            window.rootViewController = nil
            overlayController = nil
            overlayWindow = nil
        }
        guard animated else {
            finish()
            return
        }
        UIView.animate(withDuration: 0.24, animations: {
            window.alpha = 0
        }, completion: { _ in finish() })
    }
}

@MainActor
private final class AEMotionLaunchExperienceViewController: UIViewController {
    var onJoinChannel: (() -> Void)?
    var onCloseChannel: (() -> Void)?

    private let loadingStack = UIStackView()
    private let channelStack = UIStackView()
    private let progressView = UIProgressView(progressViewStyle: .default)
    private let ringLayer = CAShapeLayer()
    nonisolated(unsafe) private var progressTimer: Timer?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(white: 0.02, alpha: 1)
        configureLoadingPhase()
        configureChannelPhase()
        startAnimation()
    }

    deinit {
        progressTimer?.invalidate()
    }

    func showOfficialChannel() {
        progressTimer?.invalidate()
        channelStack.isHidden = false
        channelStack.alpha = 0
        channelStack.transform = CGAffineTransform(translationX: 0, y: 18).scaledBy(x: 0.96, y: 0.96)
        UIView.animate(withDuration: 0.32, delay: 0, options: [.curveEaseOut]) {
            self.loadingStack.alpha = 0
            self.loadingStack.transform = CGAffineTransform(translationX: 0, y: -16).scaledBy(x: 0.96, y: 0.96)
            self.channelStack.alpha = 1
            self.channelStack.transform = .identity
        } completion: { _ in
            self.loadingStack.isHidden = true
        }
    }

    private func configureLoadingPhase() {
        let logo = UILabel()
        logo.text = "Ae"
        logo.textColor = .white
        logo.textAlignment = .center
        logo.font = .systemFont(ofSize: 42, weight: .bold)
        logo.backgroundColor = UIColor(red: 0.45, green: 0.20, blue: 0.98, alpha: 1)
        logo.layer.cornerRadius = 28
        logo.clipsToBounds = true
        logo.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            logo.widthAnchor.constraint(equalToConstant: 112),
            logo.heightAnchor.constraint(equalToConstant: 112),
        ])

        let title = makeLabel("AE Motion", size: 34, weight: .bold, color: .white)
        let subtitle = makeLabel("Preparing Motion Workspace", size: 17, weight: .semibold, color: UIColor(white: 0.68, alpha: 1))
        let build = makeLabel("2.7.2 · Build 846", size: 13, weight: .medium, color: UIColor(white: 0.48, alpha: 1))

        progressView.progressTintColor = UIColor(red: 0.46, green: 0.21, blue: 1, alpha: 1)
        progressView.trackTintColor = UIColor(white: 0.18, alpha: 1)
        progressView.progress = 0.08
        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.widthAnchor.constraint(equalToConstant: 220).isActive = true

        loadingStack.axis = .vertical
        loadingStack.alignment = .center
        loadingStack.spacing = 14
        loadingStack.translatesAutoresizingMaskIntoConstraints = false
        [logo, title, subtitle, progressView, build].forEach(loadingStack.addArrangedSubview)
        view.addSubview(loadingStack)
        NSLayoutConstraint.activate([
            loadingStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingStack.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -14),
            loadingStack.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 28),
            loadingStack.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -28),
        ])

        let ringPath = UIBezierPath(arcCenter: CGPoint(x: 56, y: 56), radius: 51, startAngle: -.pi / 2, endAngle: .pi * 1.5, clockwise: true)
        ringLayer.path = ringPath.cgPath
        ringLayer.strokeColor = UIColor.white.withAlphaComponent(0.28).cgColor
        ringLayer.fillColor = UIColor.clear.cgColor
        ringLayer.lineWidth = 3
        ringLayer.lineCap = .round
        logo.layer.addSublayer(ringLayer)
    }

    private func configureChannelPhase() {
        let title = makeLabel("AE Motion iOS", size: 33, weight: .bold, color: .white)
        let subtitle = makeLabel("Official Channel", size: 20, weight: .semibold, color: UIColor(red: 0.66, green: 0.49, blue: 1, alpha: 1))
        let message = makeLabel(
            "Get release notes, update files, and support from the official AE Motion Telegram channel.",
            size: 16,
            weight: .medium,
            color: UIColor(white: 0.70, alpha: 1)
        )
        message.numberOfLines = 0
        message.textAlignment = .center

        let join = makeButton(title: "Join AE Motion Telegram", color: UIColor(red: 0.13, green: 0.58, blue: 0.95, alpha: 1))
        join.accessibilityIdentifier = "aemotion.launch.join-telegram"
        join.addAction(UIAction { [weak self] _ in self?.onJoinChannel?() }, for: .touchUpInside)

        let close = makeButton(title: "Continue to AE Motion", color: UIColor(red: 0.45, green: 0.20, blue: 0.98, alpha: 1))
        close.accessibilityIdentifier = "aemotion.launch.continue"
        close.addAction(UIAction { [weak self] _ in self?.onCloseChannel?() }, for: .touchUpInside)

        channelStack.axis = .vertical
        channelStack.alignment = .fill
        channelStack.spacing = 18
        channelStack.isHidden = true
        channelStack.translatesAutoresizingMaskIntoConstraints = false
        [title, subtitle, message, join, close].forEach(channelStack.addArrangedSubview)
        view.addSubview(channelStack)
        NSLayoutConstraint.activate([
            channelStack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            channelStack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 28),
            channelStack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -28),
            join.heightAnchor.constraint(equalToConstant: 58),
            close.heightAnchor.constraint(equalToConstant: 58),
        ])
    }

    private func startAnimation() {
        let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
        rotation.fromValue = 0
        rotation.toValue = Double.pi * 2
        rotation.duration = 1.5
        rotation.repeatCount = .infinity
        ringLayer.add(rotation, forKey: "aemotion.launch.rotation")

        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.progressView.progress = min(0.92, self.progressView.progress + 0.018)
            }
        }
    }

    private func makeLabel(_ text: String, size: CGFloat, weight: UIFont.Weight, color: UIColor) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.textAlignment = .center
        return label
    }

    private func makeButton(title: String, color: UIColor) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 18, weight: .bold)
        button.backgroundColor = color
        button.layer.cornerRadius = 16
        button.layer.cornerCurve = .continuous
        return button
    }
}
#endif
