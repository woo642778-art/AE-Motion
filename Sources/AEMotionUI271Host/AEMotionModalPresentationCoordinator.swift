#if canImport(UIKit)
import UIKit
import AEMotionExtensionsCore

@MainActor
final class AEMotionModalPresentationCoordinator: NSObject, UIAdaptivePresentationControllerDelegate {
    private weak var presenter: UIViewController?
    private var activeRoute: AEMotionModalRoute?
    private var dismissalHandler: (() -> Void)?
    private var didReportDismissal = false

    init(presenter: UIViewController) {
        self.presenter = presenter
        super.init()
    }

    func presentSettings(
        completion: @escaping (Bool) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        presentStoryboard(
            name: "SettingsNC",
            route: .settings,
            completion: completion,
            onDismiss: onDismiss
        )
    }

    func presentAccount(
        completion: @escaping (Bool) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        presentStoryboard(
            name: "MyAccountVC",
            route: .account,
            completion: completion,
            onDismiss: onDismiss
        )
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        reportDismissalOnce()
    }

    private func presentStoryboard(
        name: String,
        route: AEMotionModalRoute,
        completion: @escaping (Bool) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        guard activeRoute == nil,
              let presenter,
              presenter.presentedViewController == nil,
              let destination = UIStoryboard(name: name, bundle: .main)
                .instantiateInitialViewController() else {
            completion(false)
            return
        }

        didReportDismissal = false
        dismissalHandler = onDismiss
        activeRoute = route

        let navigation: UINavigationController
        if let existingNavigation = destination as? UINavigationController {
            navigation = existingNavigation
        } else {
            navigation = UINavigationController(rootViewController: destination)
        }
        navigation.modalPresentationStyle = .fullScreen
        navigation.presentationController?.delegate = self

        let visible = navigation.visibleViewController ?? navigation.viewControllers.first
        visible?.navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(closeActiveModal)
        )

        presenter.present(navigation, animated: true) { [weak self, weak navigation] in
            navigation?.presentationController?.delegate = self
            completion(true)
        }
    }

    @objc private func closeActiveModal() {
        guard let presenter,
              presenter.presentedViewController != nil else {
            reportDismissalOnce()
            return
        }
        presenter.dismiss(animated: true) { [weak self] in
            self?.reportDismissalOnce()
        }
    }

    private func reportDismissalOnce() {
        guard !didReportDismissal else { return }
        didReportDismissal = true
        activeRoute = nil
        let handler = dismissalHandler
        dismissalHandler = nil
        handler?()
    }
}
#endif
