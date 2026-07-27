#if canImport(UIKit)
import UIKit

@MainActor
final class AEMotionProjectActionCoordinator {
    private weak var hostController: UIViewController?
    private let studioRouter = AEMotionStudioRouter()
    private let maximumEditorPolls = 40
    private let editorPollDelay: TimeInterval = 0.10

    init(hostController: UIViewController) {
        self.hostController = hostController
    }

    @discardableResult
    func perform(
        _ action: AEMotionHomeAction,
        controls: [AEMotionHomeAction: UIControl]
    ) -> Bool {
        guard let hostController else { return false }

        switch action {
        case .threeDStudio:
            return openStudio(.threeD, controls: controls, from: hostController)
        case .worldStudio:
            return openStudio(.world, controls: controls, from: hostController)
        case .precompose, .tracking, .matte, .depthMap, .textTool,
             .speedRemap, .cutout, .presetStudio:
            guard let target = controls[action] else { return false }
            if activeProjectEditor() != nil {
                target.sendActions(for: .touchUpInside)
                return true
            }
            guard let continueEditing = controls[.continueEditing] else {
                showOpenProjectAlert(from: hostController)
                return false
            }
            continueEditing.sendActions(for: .touchUpInside)
            waitForEditor(target: target, presenter: hostController, remaining: maximumEditorPolls)
            return true
        default:
            guard let control = controls[action] else { return false }
            control.sendActions(for: .touchUpInside)
            return true
        }
    }

    private func openStudio(
        _ kind: AEMotionStudioKind,
        controls: [AEMotionHomeAction: UIControl],
        from presenter: UIViewController
    ) -> Bool {
        if let editor = activeProjectEditor() {
            return studioRouter.present(kind, from: editor)
        }
        guard let continueEditing = controls[.continueEditing] else {
            return studioRouter.present(kind, from: presenter)
        }
        continueEditing.sendActions(for: .touchUpInside)
        waitForEditor(kind: kind, presenter: presenter, remaining: maximumEditorPolls)
        return true
    }

    private func waitForEditor(
        target: UIControl,
        presenter: UIViewController,
        remaining: Int
    ) {
        guard remaining > 0 else {
            showOpenProjectAlert(from: presenter)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + editorPollDelay) { [weak self, weak target, weak presenter] in
            guard let self, let target, let presenter else { return }
            if self.activeProjectEditor() != nil {
                target.sendActions(for: .touchUpInside)
            } else {
                self.waitForEditor(target: target, presenter: presenter, remaining: remaining - 1)
            }
        }
    }

    private func waitForEditor(
        kind: AEMotionStudioKind,
        presenter: UIViewController,
        remaining: Int
    ) {
        guard remaining > 0 else {
            _ = studioRouter.present(kind, from: presenter)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + editorPollDelay) { [weak self, weak presenter] in
            guard let self, let presenter else { return }
            if let editor = self.activeProjectEditor() {
                _ = self.studioRouter.present(kind, from: editor)
            } else {
                self.waitForEditor(kind: kind, presenter: presenter, remaining: remaining - 1)
            }
        }
    }

    private func activeProjectEditor() -> UIViewController? {
        for scene in UIApplication.shared.connectedScenes {
            guard scene.activationState == .foregroundActive,
                  let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows where !window.isHidden {
                if let editor = findProjectEditor(in: window.rootViewController) {
                    return editor
                }
            }
        }
        return nil
    }

    private func findProjectEditor(in controller: UIViewController?) -> UIViewController? {
        guard let controller else { return nil }
        let className = String(describing: type(of: controller))
        let qualifiedName = NSStringFromClass(type(of: controller))
        if className.contains("ProjectEditVC") || qualifiedName.contains("ProjectEditVC") {
            return controller
        }
        if let presented = controller.presentedViewController,
           let found = findProjectEditor(in: presented) {
            return found
        }
        if let navigation = controller as? UINavigationController,
           let found = findProjectEditor(in: navigation.visibleViewController) {
            return found
        }
        if let tab = controller as? UITabBarController,
           let found = findProjectEditor(in: tab.selectedViewController) {
            return found
        }
        for child in controller.children.reversed() {
            if let found = findProjectEditor(in: child) { return found }
        }
        return nil
    }

    private func showOpenProjectAlert(from presenter: UIViewController) {
        let alert = UIAlertController(
            title: "Open a project first",
            message: "AE Motion could not find an active Project Editor. Open an existing project, then choose the tool again.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        studioRouter.topPresenter(from: presenter).present(alert, animated: true)
    }
}
#endif
