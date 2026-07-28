#if canImport(UIKit)
import UIKit

@MainActor
enum AEMotionLaunchBrandingSanitizer {
    static let officialChannelURL = URL(string: "https://t.me/aemotionios")!

    private static let maximumScans = 40
    private static let scanInterval: TimeInterval = 0.15
    private static var hasInstalled = false
    private static var scanCount = 0
    private static var observers: [NSObjectProtocol] = []
    private static var pendingWorkItem: DispatchWorkItem?

    static func install() {
        guard !hasInstalled else { return }
        hasInstalled = true
        scanCount = 0

        let center = NotificationCenter.default
        for name in [
            UIApplication.didBecomeActiveNotification,
            UIWindow.didBecomeVisibleNotification,
        ] {
            observers.append(center.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { _ in
                Task { @MainActor in scheduleNextScan() }
            })
        }
        scheduleNextScan()
    }

    static func sanitizeNow() {
        suppressVerifiedLegacyPromotion()
    }

    private static func scheduleNextScan() {
        guard scanCount < maximumScans,
              pendingWorkItem == nil else {
            if scanCount >= maximumScans {
                stop()
            }
            return
        }

        let item = DispatchWorkItem {
            Task { @MainActor in
                pendingWorkItem = nil
                scanCount += 1
                suppressVerifiedLegacyPromotion()
                if scanCount < maximumScans {
                    scheduleNextScan()
                } else {
                    stop()
                }
            }
        }
        pendingWorkItem = item
        DispatchQueue.main.asyncAfter(
            deadline: .now() + scanInterval,
            execute: item
        )
    }

    private static func stop() {
        pendingWorkItem?.cancel()
        pendingWorkItem = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
    }

    private static func suppressVerifiedLegacyPromotion() {
        for scene in UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows where !window.isHidden {
                if window.windowLevel > .normal,
                   isVerifiedLegacyPromotion(in: window) {
                    window.isHidden = true
                    window.rootViewController = nil
                    continue
                }

                guard window.windowLevel == .normal,
                      let root = window.rootViewController else { continue }

                if let presented = root.presentedViewController,
                   isVerifiedLegacyPromotion(controller: presented) {
                    presented.dismiss(animated: false)
                }

                hideVerifiedLegacyOverlaySubview(in: window)
            }
        }
    }

    private static func isVerifiedLegacyPromotion(
        controller: UIViewController
    ) -> Bool {
        guard !containsOfficialChannelIdentifier(in: controller.view) else {
            return false
        }

        let className = NSStringFromClass(type(of: controller)).lowercased()
        let classSignature = className.contains("blatant")
            || className.contains("promotion")
            || className.contains("telegram")
        let buttonStructure = hasLegacyButtonStructure(in: controller.view)
        return (classSignature && buttonStructure)
            || isVerifiedLegacyPromotion(in: controller.view)
    }

    private static func isVerifiedLegacyPromotion(in view: UIView) -> Bool {
        guard !containsOfficialChannelIdentifier(in: view) else { return false }

        let strings = allText(in: view).map(normalize)
        let hasOriginalBranding = strings.contains { value in
            value.contains("blatant")
                || value.contains("cracked by")
                || value.contains("t.me/blatants")
        }
        let hasNeutralizedBranding = strings.contains { $0.contains("ae core") }
            && strings.contains { value in
                value == "ae motion" || value.hasPrefix("ae motion ")
            }
        return (hasOriginalBranding || hasNeutralizedBranding)
            && hasLegacyButtonStructure(in: view)
    }

    private static func hasLegacyButtonStructure(in view: UIView) -> Bool {
        let buttons = allViews(in: view).compactMap { $0 as? UIButton }
        let titles = buttons.flatMap { button in
            [button.title(for: .normal), button.accessibilityLabel]
                .compactMap { $0 }
                .map(normalize)
        }
        let hasClose = titles.contains {
            $0 == "close" || $0.contains("continue")
        }
        let hasTelegram = titles.contains {
            $0.contains("telegram") || $0.contains("ae telegram")
        }
        return hasClose && hasTelegram
    }

    private static func hideVerifiedLegacyOverlaySubview(in root: UIView) {
        for subview in root.subviews.reversed() {
            guard !containsOfficialChannelIdentifier(in: subview),
                  isVerifiedLegacyPromotion(in: subview) else { continue }
            subview.isHidden = true
            subview.isUserInteractionEnabled = false
            subview.removeFromSuperview()
            return
        }
    }

    private static func containsOfficialChannelIdentifier(in root: UIView) -> Bool {
        allViews(in: root).contains {
            $0.accessibilityIdentifier == "aemotion.official-channel.root"
                || $0.accessibilityIdentifier?.hasPrefix("aemotion.official-channel.") == true
        }
    }

    private static func allText(in root: UIView) -> [String] {
        allViews(in: root).flatMap { view -> [String] in
            var values: [String] = []
            if let label = view as? UILabel, let text = label.text {
                values.append(text)
            }
            if let textView = view as? UITextView, let text = textView.text {
                values.append(text)
            }
            if let field = view as? UITextField, let text = field.text {
                values.append(text)
            }
            if let button = view as? UIButton,
               let title = button.title(for: .normal) {
                values.append(title)
            }
            if let label = view.accessibilityLabel {
                values.append(label)
            }
            if let value = view.accessibilityValue {
                values.append(value)
            }
            return values
        }
    }

    private static func allViews(in root: UIView) -> [UIView] {
        var result: [UIView] = []
        var queue: [UIView] = [root]
        while let view = queue.first {
            queue.removeFirst()
            result.append(view)
            queue.append(contentsOf: view.subviews)
        }
        return result
    }

    private static func normalize(_ value: String) -> String {
        value
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
#endif
