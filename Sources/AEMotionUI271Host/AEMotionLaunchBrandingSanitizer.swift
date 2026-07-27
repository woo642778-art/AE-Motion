#if canImport(UIKit)
import UIKit
import ObjectiveC.runtime

@MainActor
enum AEMotionLaunchBrandingSanitizer {
    static let officialChannelURL = URL(string: "https://t.me/aemotionios")!

    private static var hasInstalled = false

    static func install() {
        guard !hasInstalled else { return }
        hasInstalled = true
        swizzle(
            original: NSSelectorFromString("openURL:"),
            replacement: NSSelectorFromString("aemotion272_openURL:")
        )
        swizzle(
            original: NSSelectorFromString("openURL:options:completionHandler:"),
            replacement: NSSelectorFromString("aemotion272_openURL:options:completionHandler:")
        )
    }

    static func redirectedTelegramURL(_ url: URL) -> URL {
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == "tg" { return officialChannelURL }

        let host = url.host?.lowercased() ?? ""
        let telegramHosts = ["t.me", "www.t.me", "telegram.me", "www.telegram.me"]
        guard telegramHosts.contains(host) else { return url }

        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        return path == "aemotionios" ? url : officialChannelURL
    }

    private static func swizzle(original: Selector, replacement: Selector) {
        guard let originalMethod = class_getInstanceMethod(UIApplication.self, original),
              let replacementMethod = class_getInstanceMethod(UIApplication.self, replacement) else {
            return
        }
        method_exchangeImplementations(originalMethod, replacementMethod)
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
