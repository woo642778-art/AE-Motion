#if canImport(UIKit) && canImport(Photos)
import UIKit
import Photos

private final class WeakControllerBox: @unchecked Sendable {
    weak var value: UIViewController?
    init(_ value: UIViewController?) { self.value = value }
}

@MainActor
enum TimelineHandoffCoordinator {
    enum HandoffError: Error, LocalizedError, Sendable {
        case photoPermissionDenied
        case photoSaveFailed(String)
        case projectEditorNotFound

        var errorDescription: String? {
            switch self {
            case .photoPermissionDenied:
                return "Photo-library add permission was not granted."
            case .photoSaveFailed(let message):
                return message
            case .projectEditorNotFound:
                return "The rendered clip was saved to Photos, but the active Alight Motion project editor could not be found."
            }
        }
    }

    /// Stable handoff used by all render tools.
    /// The rendered file is saved as the newest Photos video and the extension UI is closed
    /// back toward the active project editor. It intentionally does not invoke private
    /// addLayer selectors because those calls caused a completion-time crash on device.
    static func renderResultReady(
        fileURL: URL,
        from controller: UIViewController,
        completion: @escaping @MainActor @Sendable (Result<Void, HandoffError>) -> Void
    ) {
        let controllerBox = WeakControllerBox(controller)
        requestAddAuthorization { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success:
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
                }) { success, error in
                    Task { @MainActor in
                        guard success else {
                            completion(.failure(.photoSaveFailed(
                                error?.localizedDescription ?? "Could not save the rendered clip to Photos."
                            )))
                            return
                        }
                        guard let controller = controllerBox.value else {
                            completion(.failure(.projectEditorNotFound))
                            return
                        }
                        guard let projectEditor = findProjectEditor() else {
                            completion(.failure(.projectEditorNotFound))
                            return
                        }

                        completion(.success(()))
                        DispatchQueue.main.async {
                            closeToolUI(from: controller, toward: projectEditor)
                        }
                    }
                }
            }
        }
    }

    private static func requestAddAuthorization(
        completion: @escaping @MainActor @Sendable (Result<Void, HandoffError>) -> Void
    ) {
        let current = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if current == .authorized || current == .limited {
            completion(.success(()))
            return
        }
        if current == .denied || current == .restricted {
            completion(.failure(.photoPermissionDenied))
            return
        }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            Task { @MainActor in
                if status == .authorized || status == .limited {
                    completion(.success(()))
                } else {
                    completion(.failure(.photoPermissionDenied))
                }
            }
        }
    }

    private static func closeToolUI(
        from controller: UIViewController,
        toward projectEditor: UIViewController
    ) {
        if let navigation = controller.navigationController,
           navigation.viewControllers.contains(where: { $0 === projectEditor }) {
            navigation.popToViewController(projectEditor, animated: true)
            return
        }

        if controller.presentingViewController != nil {
            controller.dismiss(animated: true)
            return
        }

        if let navigation = controller.navigationController,
           navigation.viewControllers.count > 1 {
            navigation.popViewController(animated: true)
        }
    }

    private static func findProjectEditor() -> UIViewController? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .filter { !$0.isHidden }
            .sorted { lhs, rhs in
                if lhs.isKeyWindow != rhs.isKeyWindow { return lhs.isKeyWindow }
                return lhs.windowLevel.rawValue > rhs.windowLevel.rawValue
            }

        for window in windows {
            guard let root = window.rootViewController else { continue }
            var visited = Set<ObjectIdentifier>()
            if let match = findProjectEditor(in: root, visited: &visited) {
                return match
            }
        }
        return nil
    }

    private static func findProjectEditor(
        in controller: UIViewController,
        visited: inout Set<ObjectIdentifier>
    ) -> UIViewController? {
        guard visited.insert(ObjectIdentifier(controller)).inserted else { return nil }
        let className = NSStringFromClass(type(of: controller))
        if className.localizedCaseInsensitiveContains("ProjectEditVC") {
            return controller
        }

        if let presented = controller.presentedViewController,
           let match = findProjectEditor(in: presented, visited: &visited) {
            return match
        }
        if let navigation = controller as? UINavigationController {
            for child in navigation.viewControllers.reversed() {
                if let match = findProjectEditor(in: child, visited: &visited) { return match }
            }
        }
        if let tab = controller as? UITabBarController {
            for child in (tab.viewControllers ?? []).reversed() {
                if let match = findProjectEditor(in: child, visited: &visited) { return match }
            }
        }
        for child in controller.children.reversed() {
            if let match = findProjectEditor(in: child, visited: &visited) { return match }
        }
        return nil
    }
}
#endif
