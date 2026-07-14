#if canImport(UIKit)
import UIKit

@MainActor
enum ToolPresentationGuard {
    static func destination(for toolID: String) -> UIViewController {
        switch ToolControllerFactory.buildResult(for: toolID) {
        case .ready(let controller):
            return controller
        case .unavailable(let title, let reason):
            return UnavailableToolViewController(toolTitle: title, reason: reason)
        }
    }

    static func push(_ toolID: String, from navigationController: UINavigationController?) {
        guard let navigationController else { return }
        let destination = destination(for: toolID)
        navigationController.pushViewController(destination, animated: true)
    }

    static func present(_ toolID: String, from presenter: UIViewController) {
        guard presenter.presentedViewController == nil else { return }
        let destination = destination(for: toolID)
        let navigation = UINavigationController(rootViewController: destination)
        navigation.modalPresentationStyle = .pageSheet
        presenter.present(navigation, animated: true)
    }
}
#endif
