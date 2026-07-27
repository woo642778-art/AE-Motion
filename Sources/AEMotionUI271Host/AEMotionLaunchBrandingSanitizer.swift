#if canImport(UIKit)
import UIKit
import ObjectiveC.runtime

@MainActor
enum AEMotionLaunchBrandingSanitizer {
    static let officialChannelURL = URL(string: "https://t.me/aemotionios")!

    private static var hasInstalled = false
    private static var observers: [NSObjectProtocol] = []
    private static var scanGeneration = 0

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
            }
        }
    }

    private static func sanitizeVisiblePromotionWindows() {
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows where !window.isHidden && window.alpha > 0.01 {
                guard containsLegacyPromotionMarker(in: window) else { continue }
                sanitizePromotionTree(window)
            }
        }
    }

    private static func containsLegacyPromotionMarker(in view: UIView) -> Bool {
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

        for subview in view.subviews {
            sanitizePromotionTree(subview)
        }
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
