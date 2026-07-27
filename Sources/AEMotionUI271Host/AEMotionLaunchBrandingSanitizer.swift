#if canImport(UIKit)
import UIKit
import ObjectiveC.runtime

@MainActor
enum AEMotionLaunchBrandingSanitizer {
    static let officialChannelURL = URL(string: "https://t.me/aemotionios")!

    private static let dismissedKey = "aemotion.launch.branding842.dismissed"
    private static var hasInstalled = false
    private static var observers: [NSObjectProtocol] = []
    private static var scanGeneration = 0
    private static var activeOverlay: AEMotionLaunchPromotionOverlay?

    static func install() {
        guard !hasInstalled else {
            scheduleSanitizationBurst()
            return
        }
        hasInstalled = true
        installTelegramURLRedirects()

        let center = NotificationCenter.default
        for name in [
            UIApplication.didFinishLaunchingNotification,
            UIApplication.didBecomeActiveNotification,
            UIWindow.didBecomeVisibleNotification,
        ] {
            observers.append(center.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { _ in
                Task { @MainActor in scheduleSanitizationBurst() }
            })
        }
        scheduleSanitizationBurst()
    }

    static func redirectedTelegramURL(_ url: URL) -> URL {
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == "tg" { return officialChannelURL }

        let host = url.host?.lowercased() ?? ""
        let telegramHosts = ["t.me", "www.t.me", "telegram.me", "www.telegram.me"]
        guard telegramHosts.contains(host) else { return url }

        let normalizedPath = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        return normalizedPath == "aemotionios" ? url : officialChannelURL
    }

    private static func installTelegramURLRedirects() {
        swizzle(
            original: NSSelectorFromString("openURL:"),
            replacement: NSSelectorFromString("aemotion272_openURL:")
        )
        swizzle(
            original: NSSelectorFromString("openURL:options:completionHandler:"),
            replacement: NSSelectorFromString("aemotion272_openURL:options:completionHandler:")
        )
    }

    private static func swizzle(original: Selector, replacement: Selector) {
        guard let originalMethod = class_getInstanceMethod(UIApplication.self, original),
              let replacementMethod = class_getInstanceMethod(UIApplication.self, replacement) else {
            return
        }
        method_exchangeImplementations(originalMethod, replacementMethod)
    }

    private static func scheduleSanitizationBurst() {
        scanGeneration += 1
        let generation = scanGeneration
        for attempt in 0..<48 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(attempt) * 0.25) {
                guard generation == scanGeneration else { return }
                sanitizeVisiblePromotionWindows()
                presentReplacementPromotionIfNeeded()
            }
        }
    }

    private static func visibleWindows() -> [UIWindow] {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .filter { !$0.isHidden && $0.alpha > 0.01 }
    }

    private static func preferredPresentationWindow() -> UIWindow? {
        visibleWindows().sorted {
            if $0.windowLevel == $1.windowLevel { return !$0.isKeyWindow && $1.isKeyWindow }
            return $0.windowLevel.rawValue < $1.windowLevel.rawValue
        }.last
    }

    private static func presentReplacementPromotionIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: dismissedKey),
              activeOverlay == nil,
              let window = preferredPresentationWindow() else { return }

        let overlay = AEMotionLaunchPromotionOverlay()
        overlay.onJoin = {
            UIApplication.shared.open(officialChannelURL, options: [:], completionHandler: nil)
        }
        overlay.onClose = {
            UserDefaults.standard.set(true, forKey: dismissedKey)
            sanitizeVisiblePromotionWindows()
            dismissUnderlyingLegacyPromotion(excluding: overlay)
            overlay.isUserInteractionEnabled = false
            UIView.animate(withDuration: 0.18, animations: {
                overlay.alpha = 0
            }, completion: { _ in
                overlay.removeFromSuperview()
                activeOverlay = nil
            })
        }
        activeOverlay = overlay
        overlay.translatesAutoresizingMaskIntoConstraints = false
        window.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.leadingAnchor.constraint(equalTo: window.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: window.trailingAnchor),
            overlay.topAnchor.constraint(equalTo: window.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: window.bottomAnchor),
        ])
        window.bringSubviewToFront(overlay)
    }

    private static func sanitizeVisiblePromotionWindows() {
        for window in visibleWindows() {
            guard containsLegacyPromotionMarker(in: window) else { continue }
            sanitizePromotionTree(window)
        }
    }

    private static func containsLegacyPromotionMarker(in view: UIView) -> Bool {
        let accessibility = [view.accessibilityLabel, view.accessibilityValue]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        if accessibility.contains("blatant")
            || accessibility.contains("cracked by")
            || accessibility.contains("my telegram") {
            return true
        }
        if let label = view as? UILabel,
           let text = label.text?.lowercased(),
           text.contains("blatant") || text.contains("cracked by") {
            return true
        }
        if let button = view as? UIButton {
            let title = button.configuration?.title ?? button.title(for: .normal) ?? ""
            if title.lowercased().contains("my telegram") { return true }
        }
        return view.subviews.contains { containsLegacyPromotionMarker(in: $0) }
    }

    private static func sanitizePromotionTree(_ view: UIView) {
        let accessibility = [view.accessibilityLabel, view.accessibilityValue]
            .compactMap { $0 }
            .joined(separator: " ")
        if accessibility.localizedCaseInsensitiveContains("Blatant")
            || accessibility.localizedCaseInsensitiveContains("Cracked By") {
            view.accessibilityLabel = "AE Motion iOS"
            view.accessibilityValue = nil
        }

        if let label = view as? UILabel,
           let text = label.text,
           text.localizedCaseInsensitiveContains("Blatant")
                || text.localizedCaseInsensitiveContains("Cracked By") {
            label.text = "AE Motion iOS"
            label.accessibilityLabel = "AE Motion iOS"
        }

        if let button = view as? UIButton {
            let currentTitle = button.configuration?.title ?? button.title(for: .normal) ?? ""
            if currentTitle.localizedCaseInsensitiveContains("Telegram") {
                if var configuration = button.configuration {
                    configuration.title = "Join AE Motion Telegram"
                    button.configuration = configuration
                } else {
                    button.setTitle("Join AE Motion Telegram", for: .normal)
                }
                button.accessibilityIdentifier = "aemotion.launch.join-channel"
                button.accessibilityLabel = "Join AE Motion Telegram"
            }
        }

        for subview in view.subviews where subview !== activeOverlay {
            sanitizePromotionTree(subview)
        }
    }

    private static func dismissUnderlyingLegacyPromotion(excluding overlay: UIView) {
        for window in visibleWindows() {
            activateCloseControls(in: window, excluding: overlay)
            if let presented = window.rootViewController?.presentedViewController,
               containsLegacyPromotionMarker(in: presented.view) {
                presented.dismiss(animated: false)
            }
        }
    }

    private static func activateCloseControls(in view: UIView, excluding overlay: UIView) {
        guard view !== overlay, !view.isDescendant(of: overlay) else { return }
        let accessibleTitle = view.accessibilityLabel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if let button = view as? UIButton {
            let title = button.configuration?.title ?? button.title(for: .normal) ?? accessibleTitle
            if title.caseInsensitiveCompare("Close") == .orderedSame {
                button.sendActions(for: .touchUpInside)
            }
        } else if let control = view as? UIControl,
                  accessibleTitle.caseInsensitiveCompare("Close") == .orderedSame {
            control.sendActions(for: .touchUpInside)
        } else if accessibleTitle.caseInsensitiveCompare("Close") == .orderedSame {
            _ = view.accessibilityActivate()
        }

        for subview in view.subviews {
            activateCloseControls(in: subview, excluding: overlay)
        }
    }
}

@MainActor
private final class AEMotionLaunchPromotionOverlay: UIView {
    var onJoin: (() -> Void)?
    var onClose: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        accessibilityIdentifier = "aemotion.launch.replacement-overlay"
        backgroundColor = UIColor(white: 0.025, alpha: 1)
        configureHierarchy()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func configureHierarchy() {
        let title = UILabel()
        title.text = "Welcome 👋"
        title.font = .systemFont(ofSize: 34, weight: .bold)
        title.textColor = .white
        title.textAlignment = .center

        let subtitle = UILabel()
        subtitle.text = "AE Motion iOS"
        subtitle.font = .systemFont(ofSize: 23, weight: .semibold)
        subtitle.textColor = UIColor(white: 0.72, alpha: 1)
        subtitle.textAlignment = .center

        let message = UILabel()
        message.text = "Updates, release notes, and support are available in the official AE Motion channel."
        message.font = .systemFont(ofSize: 16, weight: .medium)
        message.textColor = UIColor(white: 0.65, alpha: 1)
        message.textAlignment = .center
        message.numberOfLines = 0

        let join = makeButton(title: "Join AE Motion Telegram", backgroundColor: .systemBlue)
        join.accessibilityIdentifier = "aemotion.launch.join-channel"
        join.addAction(UIAction { [weak self] _ in self?.onJoin?() }, for: .touchUpInside)

        let close = makeButton(title: "Close", backgroundColor: .systemRed)
        close.accessibilityIdentifier = "aemotion.launch.close"
        close.addAction(UIAction { [weak self] _ in self?.onClose?() }, for: .touchUpInside)

        let header = UIStackView(arrangedSubviews: [title, subtitle, message])
        header.axis = .vertical
        header.alignment = .fill
        header.spacing = 24
        header.translatesAutoresizingMaskIntoConstraints = false

        let buttons = UIStackView(arrangedSubviews: [join, close])
        buttons.axis = .vertical
        buttons.spacing = 18
        buttons.translatesAutoresizingMaskIntoConstraints = false

        addSubview(header)
        addSubview(buttons)
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 28),
            header.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -28),
            header.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 62),
            buttons.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 22),
            buttons.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -22),
            buttons.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -28),
            join.heightAnchor.constraint(equalToConstant: 58),
            close.heightAnchor.constraint(equalToConstant: 58),
        ])
    }

    private func makeButton(title: String, backgroundColor: UIColor) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle(title, for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 20, weight: .bold)
        button.backgroundColor = backgroundColor
        button.layer.cornerRadius = 14
        button.layer.cornerCurve = .continuous
        return button
    }
}

@MainActor
private extension UIApplication {
    @objc(aemotion272_openURL:)
    func aemotion272_openURL(_ url: URL) -> Bool {
        aemotion272_openURL(AEMotionLaunchBrandingSanitizer.redirectedTelegramURL(url))
    }

    @objc(aemotion272_openURL:options:completionHandler:)
    func aemotion272_openURL(
        _ url: URL,
        options: [UIApplication.OpenExternalURLOptionsKey: Any],
        completionHandler: ((Bool) -> Void)?
    ) {
        aemotion272_openURL(
            AEMotionLaunchBrandingSanitizer.redirectedTelegramURL(url),
            options: options,
            completionHandler: completionHandler
        )
    }
}
#endif
