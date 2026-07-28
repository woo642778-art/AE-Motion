#if canImport(UIKit)
import UIKit
import AEMotionExtensionsCore

@MainActor
final class AEMotionActionRouter {
    private weak var hostRootController: UIViewController?
    private weak var hostTabController: UITabBarController?
    private let studioRouter = AEMotionStudioRouter()

    init(
        hostRootController: UIViewController,
        hostTabController: UITabBarController
    ) {
        self.hostRootController = hostRootController
        self.hostTabController = hostTabController
    }

    func perform(
        _ action: AEMotionHomeAction,
        from presenter: UIViewController,
        completion: @escaping (AEMotionActionResult) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        switch action {
        case .threeDStudio:
            openStudio(.threeD, from: presenter, completion: completion, onDismiss: onDismiss)
        case .worldStudio:
            openStudio(.world, from: presenter, completion: completion, onDismiss: onDismiss)
        case .precompose, .tracking, .matte, .depthMap, .textTool,
             .speedRemap, .cutout, .presetStudio:
            openQuickTool(action, completion: completion)
        case .newProject, .importProject, .continueEditing, .camera, .assetLibrary:
            forwardVerifiedHostAction(action, completion: completion)
        case .tutorials, .templates:
            completion(.failed("This action is handled by root navigation."))
        }
    }

    private func openStudio(
        _ kind: AEMotionStudioKind,
        from presenter: UIViewController,
        completion: @escaping (AEMotionActionResult) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        let route: AEMotionNonRootRoute = kind == .threeD
            ? .threeDStudio
            : .worldStudio
        let presented = studioRouter.present(
            kind,
            from: presenter,
            onDismiss: onDismiss
        )
        completion(
            presented
                ? .opened(route)
                : .unavailable(
                    kind == .threeD
                        ? "3D Studio could not be loaded."
                        : "Real-Time World Studio could not be loaded."
                )
        )
    }

    private func openQuickTool(
        _ action: AEMotionHomeAction,
        completion: @escaping (AEMotionActionResult) -> Void
    ) {
        guard let editor = activeProjectEditor() else {
            completion(.requiresOpenProject)
            return
        }
        guard let control = visibleControl(for: action, under: editor.view) else {
            completion(.unavailable("The selected tool is not available in the active editor."))
            return
        }

        control.sendActions(for: .touchUpInside)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
            guard control.window != nil,
                  control.isEnabled,
                  !control.isHidden,
                  control.alpha > 0.01 else {
                completion(.failed("The editor rejected the tool action."))
                return
            }
            completion(.opened(.tool))
        }
    }

    private func forwardVerifiedHostAction(
        _ action: AEMotionHomeAction,
        completion: @escaping (AEMotionActionResult) -> Void
    ) {
        guard let hostRootController else {
            completion(.failed("The host application root is unavailable."))
            return
        }
        guard let control = visibleControl(for: action, under: hostRootController.view) else {
            completion(.unavailable("The host action is not currently available."))
            return
        }

        let beforePresenter = topPresenter(from: hostRootController)
        let beforeIdentifier = ObjectIdentifier(beforePresenter)
        control.sendActions(for: .touchUpInside)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, let hostRootController = self.hostRootController else {
                completion(.failed("The host application closed the action before it completed."))
                return
            }
            let afterPresenter = self.topPresenter(from: hostRootController)
            let changedController = ObjectIdentifier(afterPresenter) != beforeIdentifier
            let editorOpened = self.activeProjectEditor() != nil

            guard changedController || editorOpened else {
                completion(.failed("The host application did not open the requested destination."))
                return
            }

            let route: AEMotionNonRootRoute
            switch action {
            case .continueEditing, .newProject, .importProject, .camera, .assetLibrary:
                route = .projectEditor
            default:
                route = .tool
            }
            completion(.opened(route))
        }
    }

    private func visibleControl(
        for action: AEMotionHomeAction,
        under root: UIView
    ) -> UIControl? {
        let keywords = keywords(for: action)
        return allDescendantsIncludingSelf(root)
            .compactMap { $0 as? UIControl }
            .first { control in
                guard isVisibleAndInteractive(control) else { return false }
                let identifier = control.accessibilityIdentifier ?? ""
                let label = control.accessibilityLabel ?? ""
                let title = (control as? UIButton)?.title(for: .normal) ?? ""
                let value = [identifier, label, title]
                    .joined(separator: " ")
                    .lowercased()
                return keywords.allSatisfy { value.contains($0) }
            }
    }

    private func isVisibleAndInteractive(_ control: UIControl) -> Bool {
        guard control.window != nil,
              control.isEnabled,
              control.isUserInteractionEnabled,
              !control.isHidden,
              control.alpha > 0.01 else { return false }

        var ancestor = control.superview
        while let view = ancestor {
            guard !view.isHidden,
                  view.alpha > 0.01,
                  view.isUserInteractionEnabled else { return false }
            ancestor = view.superview
        }
        return true
    }

    private func keywords(for action: AEMotionHomeAction) -> [String] {
        switch action {
        case .continueEditing: return ["continue"]
        case .newProject: return ["new", "project"]
        case .importProject: return ["import"]
        case .camera: return ["camera"]
        case .assetLibrary: return ["asset"]
        case .precompose: return ["pre", "comp"]
        case .tracking: return ["track"]
        case .matte: return ["matte"]
        case .depthMap: return ["depth"]
        case .textTool: return ["text"]
        case .speedRemap: return ["speed"]
        case .cutout: return ["cutout"]
        case .presetStudio: return ["preset"]
        case .threeDStudio: return ["3d", "studio"]
        case .worldStudio: return ["world", "studio"]
        case .tutorials: return ["tutorial"]
        case .templates: return ["template"]
        }
    }

    private func allDescendantsIncludingSelf(_ root: UIView) -> [UIView] {
        var result: [UIView] = []
        var queue: [UIView] = [root]
        while let view = queue.first {
            queue.removeFirst()
            result.append(view)
            queue.append(contentsOf: view.subviews)
        }
        return result
    }

    private func activeProjectEditor() -> UIViewController? {
        guard let hostRootController else { return nil }
        return findProjectEditor(in: hostRootController)
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
            if let found = findProjectEditor(in: child) {
                return found
            }
        }
        return nil
    }

    private func topPresenter(from controller: UIViewController) -> UIViewController {
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
#endif
