#if canImport(UIKit)
import UIKit

@MainActor
enum AEMotionLaunchBrandingSanitizer {
    static let officialChannelURL = URL(string: "https://t.me/aemotionios")!

    private static var hasInstalled = false
    private static var observers: [NSObjectProtocol] = []
    private static var generation = 0

    static func install() {
        guard !hasInstalled else { return }
        hasInstalled = true

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
                Task { @MainActor in scheduleSanitizationBurst() }
            })
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.40) {
            scheduleSanitizationBurst()
        }
    }

    static func sanitizeNow() {
        sanitizeVisibleLegacyPromotion()
    }

    private static func scheduleSanitizationBurst() {
        generation += 1
        let currentGeneration = generation
        for attempt in 0..<80 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(attempt) * 0.10) {
                guard currentGeneration == generation else { return }
                sanitizeVisibleLegacyPromotion()
            }
        }
    }

    private static func sanitizeVisibleLegacyPromotion() {
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows where !window.isHidden {
                if containsLegacyBranding(in: window) {
                    if window.windowLevel > .normal {
                        window.isHidden = true
                        continue
                    }

                    if let root = window.rootViewController,
                       let presented = root.presentedViewController,
                       presented.isViewLoaded,
                       containsLegacyBranding(in: presented.view) {
                        presented.dismiss(animated: false)
                        continue
                    }

                    hideLegacySubview(in: window)
                }
            }
        }
    }

    private static func hideLegacySubview(in root: UIView) {
        guard let target = firstLegacyBrandingView(in: root) else { return }
        var candidate = target
        while let superview = candidate.superview,
              superview !== root,
              coverage(of: superview, in: root) < 0.55 {
            candidate = superview
        }
        candidate.isHidden = true
        candidate.isUserInteractionEnabled = false
    }

    private static func firstLegacyBrandingView(in view: UIView) -> UIView? {
        if textFragments(in: view).contains(where: isLegacyBrandingText) {
            return view
        }
        for child in view.subviews {
            if let match = firstLegacyBrandingView(in: child) { return match }
        }
        return nil
    }

    private static func containsLegacyBranding(in view: UIView) -> Bool {
        firstLegacyBrandingView(in: view) != nil
    }

    private static func textFragments(in view: UIView) -> [String] {
        var values: [String] = []
        if let label = view as? UILabel, let text = label.text { values.append(text) }
        if let textView = view as? UITextView, let text = textView.text { values.append(text) }
        if let field = view as? UITextField, let text = field.text { values.append(text) }
        if let button = view as? UIButton {
            for state: UIControl.State in [.normal, .highlighted, .selected, .disabled] {
                if let title = button.title(for: state) { values.append(title) }
            }
        }
        if let accessibilityLabel = view.accessibilityLabel { values.append(accessibilityLabel) }
        return values
    }

    private static func isLegacyBrandingText(_ text: String) -> Bool {
        let normalized = text
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
        return normalized.contains("blatant")
            || normalized.contains("cracked by")
            || normalized.contains("my telegram")
            || normalized.contains("t.me/blatants")
    }

    private static func coverage(of view: UIView, in root: UIView) -> CGFloat {
        let rootArea = max(1, root.bounds.width * root.bounds.height)
        let frame = view.convert(view.bounds, to: root).intersection(root.bounds)
        guard !frame.isNull, !frame.isEmpty else { return 0 }
        return (frame.width * frame.height) / rootArea
    }
}
#endif
