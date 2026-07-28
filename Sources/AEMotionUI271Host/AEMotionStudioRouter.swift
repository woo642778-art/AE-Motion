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
    func present(
        _ kind: AEMotionStudioKind,
        from presenter: UIViewController,
        onDismiss: @escaping () -> Void
    ) -> Bool {
        let className = kind == .threeD
            ? threeDProjectBrowserClass
            : worldProjectBrowserClass
        guard className != rejectedProofClass,
              let objectType = NSClassFromString(className) as? NSObject.Type else {
            return false
        }

        let object = objectType.init()
        guard let browser = object as? UIViewController,
              !String(describing: type(of: browser)).contains("Proof") else {
            return false
        }

        let navigation = AEMotionStudioNavigationController(
            rootViewController: browser,
            onDismiss: onDismiss
        )
        navigation.modalPresentationStyle = .fullScreen
        topPresenter(from: presenter).present(navigation, animated: true)
        return true
    }

    func topPresenter(from controller: UIViewController) -> UIViewController {
        if let presented = controller.presentedViewController,
           !presented.isBeingDismissed {
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
        for child in controller.children.reversed()
        where child.viewIfLoaded?.window != nil {
            return topPresenter(from: child)
        }
        return controller
    }
}

@MainActor
private final class AEMotionStudioNavigationController:
    UINavigationController,
    UIAdaptivePresentationControllerDelegate
{
    private var dismissalHandler: (() -> Void)?
    private var didReportDismissal = false

    init(
        rootViewController: UIViewController,
        onDismiss: @escaping () -> Void
    ) {
        dismissalHandler = onDismiss
        super.init(rootViewController: rootViewController)
        rootViewController.navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(closeStudio)
        )
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        presentationController?.delegate = self
    }

    @objc private func closeStudio() {
        dismiss(animated: true) { [weak self] in
            self?.reportDismissalOnce()
        }
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        reportDismissalOnce()
    }

    private func reportDismissalOnce() {
        guard !didReportDismissal else { return }
        didReportDismissal = true
        let handler = dismissalHandler
        dismissalHandler = nil
        handler?()
    }
}
#endif
