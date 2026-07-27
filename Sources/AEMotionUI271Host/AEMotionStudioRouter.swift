#if canImport(UIKit)
import UIKit

@MainActor
enum AEMotionStudioKind: Sendable {
    case threeD
    case world
}

@MainActor
final class AEMotionStudioRouter {
    private let threeDProjectBrowserClass = "AEMotionExtensionsHost.ThreeDStudioProjectBrowserViewController"
    private let worldProjectBrowserClass = "AEMotionExtensionsHost.WorldStudioProjectBrowserViewController"
    private let rejectedProofClass = "AEMotionExtensionsHost.ThreeDMetalProofViewController"

    @discardableResult
    func present(_ kind: AEMotionStudioKind, from presenter: UIViewController) -> Bool {
        let className = kind == .threeD ? threeDProjectBrowserClass : worldProjectBrowserClass
        guard className != rejectedProofClass,
              let objectType = NSClassFromString(className) as? NSObject.Type else {
            showUnavailable(kind, from: presenter)
            return false
        }

        let object = objectType.init()
        guard let browser = object as? UIViewController,
              !String(describing: type(of: browser)).contains("Proof") else {
            showUnavailable(kind, from: presenter)
            return false
        }

        browser.modalPresentationStyle = .fullScreen
        let navigation = UINavigationController(rootViewController: browser)
        navigation.modalPresentationStyle = .fullScreen
        topPresenter(from: presenter).present(navigation, animated: true)
        return true
    }

    func topPresenter(from controller: UIViewController) -> UIViewController {
        if let presented = controller.presentedViewController, !presented.isBeingDismissed {
            return topPresenter(from: presented)
        }
        if let navigation = controller as? UINavigationController,
           let visible = navigation.visibleViewController {
            return topPresenter(from: visible)
        }
        if let tab = controller as? UITabBarController,
           let selected = tab.selectedViewController {
            return topPresenter(from: selected)
        }
        for child in controller.children.reversed() where child.viewIfLoaded?.window != nil {
            return topPresenter(from: child)
        }
        return controller
    }

    private func showUnavailable(_ kind: AEMotionStudioKind, from presenter: UIViewController) {
        let title = kind == .threeD ? "3D Studio unavailable" : "World Studio unavailable"
        let message = "The production workspace could not be loaded. The proof/demo controller was not used."
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        topPresenter(from: presenter).present(alert, animated: true)
    }
}
#endif
