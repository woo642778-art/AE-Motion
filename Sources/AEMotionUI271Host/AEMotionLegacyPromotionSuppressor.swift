#if canImport(UIKit)
import UIKit
import ObjectiveC.runtime
import Darwin

private typealias AEMotionPromotionNoop = @convention(c) (AnyObject, Selector) -> Void
private let aemotionPromotionNoop: AEMotionPromotionNoop = { _, _ in }

@MainActor
enum AEMotionLegacyPromotionSuppressor {
    private static let promotionSelector = NSSelectorFromString(
        "showTitle:title:subTitle:duration:completeText:"
    )
    private static var hasStarted = false
    private static var observers: [NSObjectProtocol] = []
    private static var patchedMethods = Set<UInt>()
    private static var scanGeneration = 0

    static func install() {
        if !hasStarted {
            hasStarted = true
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
                    Task { @MainActor in scheduleSuppressionBurst() }
                })
            }
        }
        scheduleSuppressionBurst()
    }

    private static func scheduleSuppressionBurst() {
        scanGeneration += 1
        let generation = scanGeneration
        for attempt in 0..<160 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(attempt) * 0.05) {
                guard generation == scanGeneration else { return }
                installRuntimeHooks()
                dismissVisibleLegacyPromotion()
            }
        }
    }

    private static func installRuntimeHooks() {
        var count: UInt32 = 0
        guard let classes = objc_copyClassList(&count) else { return }
        defer { free(UnsafeMutableRawPointer(classes)) }

        for index in 0..<Int(count) {
            let cls: AnyClass = classes[index]
            patchMethod(on: cls)
            if let metaclass = object_getClass(cls) {
                patchMethod(on: metaclass)
            }
        }
    }

    private static func patchMethod(on cls: AnyClass) {
        guard let method = class_getInstanceMethod(cls, promotionSelector) else { return }
        let key = UInt(bitPattern: method)
        guard !patchedMethods.contains(key) else { return }

        let implementation = method_getImplementation(method)
        guard implementationBelongsToLegacyTweak(implementation) else { return }
        let replacement = unsafeBitCast(aemotionPromotionNoop, to: IMP.self)
        method_setImplementation(method, replacement)
        patchedMethods.insert(key)
    }

    private static func implementationBelongsToLegacyTweak(_ implementation: IMP) -> Bool {
        var info = Dl_info()
        let pointer = unsafeBitCast(implementation, to: UnsafeRawPointer.self)
        guard dladdr(pointer, &info) != 0, let image = info.dli_fname else { return false }
        return String(cString: image).hasSuffix("/AlightMotion.dylib")
    }

    private static func dismissVisibleLegacyPromotion() {
        for window in visibleWindows() {
            dismissPresentedPromotion(from: window.rootViewController)
            removePromotionSubviews(from: window, window: window)
        }
    }

    private static func visibleWindows() -> [UIWindow] {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .filter { !$0.isHidden && $0.alpha > 0.01 }
    }

    private static func dismissPresentedPromotion(from controller: UIViewController?) {
        guard let controller else { return }
        if let presented = controller.presentedViewController, !presented.isBeingDismissed {
            if isLegacyPromotion(view: presented.view) {
                presented.dismiss(animated: false)
            } else {
                dismissPresentedPromotion(from: presented)
            }
        }
        for child in controller.children {
            dismissPresentedPromotion(from: child)
        }
    }

    private static func removePromotionSubviews(from view: UIView, window: UIWindow) {
        for subview in view.subviews.reversed() {
            if isLegacyPromotion(view: subview) {
                let frame = subview.convert(subview.bounds, to: window)
                let coverage = frame.width * frame.height
                let windowArea = max(1, window.bounds.width * window.bounds.height)
                if coverage / windowArea > 0.55 {
                    subview.removeFromSuperview()
                    continue
                }
            }
            removePromotionSubviews(from: subview, window: window)
        }
    }

    private static func isLegacyPromotion(view: UIView) -> Bool {
        let text = collectedText(in: view).lowercased()
        let hasBrand = text.contains("blatant")
            || text.contains("cracked by")
            || text.contains("ae motion official")
        let hasTelegram = text.contains("my telegram")
            || text.contains("join ae motion telegram")
        let hasClose = text.components(separatedBy: .whitespacesAndNewlines).contains("close")
        let hasWelcome = text.contains("welcome")
        return hasBrand || (hasWelcome && hasTelegram && hasClose)
    }

    private static func collectedText(in view: UIView) -> String {
        var values: [String] = []
        if let label = view as? UILabel {
            if let text = label.text { values.append(text) }
            if let text = label.attributedText?.string { values.append(text) }
        }
        if let button = view as? UIButton {
            if let text = button.title(for: .normal) { values.append(text) }
            if let text = button.attributedTitle(for: .normal)?.string { values.append(text) }
            if let text = button.configuration?.title { values.append(text) }
        }
        if let label = view.accessibilityLabel { values.append(label) }
        if let value = view.accessibilityValue { values.append(value) }
        for subview in view.subviews {
            values.append(collectedText(in: subview))
        }
        return values.joined(separator: " ")
    }
}
#endif
