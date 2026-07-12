#if canImport(UIKit) && canImport(Photos)
import UIKit
import Photos
import ObjectiveC.runtime

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
        case addLayerActionUnavailable

        var errorDescription: String? {
            switch self {
            case .photoPermissionDenied:
                return "Photo-library add permission was not granted."
            case .photoSaveFailed(let message):
                return message
            case .projectEditorNotFound:
                return "The active Alight Motion project editor could not be found. Return to an open project and try again."
            case .addLayerActionUnavailable:
                return "The current Alight Motion build did not expose a safe Add Layer action. The rendered clip was saved as the newest Photos item."
            }
        }
    }

    /// A low-risk handoff that avoids the share sheet: render to a temporary file,
    /// save it as the newest Photos video, return to the project editor, and open Add Layer.
    /// It deliberately does not mutate Alight Motion's private project database.
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
                            completion(.failure(HandoffError.photoSaveFailed(
                                error?.localizedDescription ?? "Could not save the rendered clip to Photos."
                            )))
                            return
                        }
                        guard let controller = controllerBox.value else {
                            completion(.failure(.projectEditorNotFound))
                            return
                        }
                        do {
                            try openAddLayerFlow(from: controller)
                            completion(.success(()))
                        } catch let error as HandoffError {
                            completion(.failure(error))
                        } catch {
                            completion(.failure(.photoSaveFailed(error.localizedDescription)))
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
            completion(.failure(HandoffError.photoPermissionDenied))
            return
        }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            Task { @MainActor in
                if status == .authorized || status == .limited {
                    completion(.success(()))
                } else {
                    completion(.failure(HandoffError.photoPermissionDenied))
                }
            }
        }
    }

    private static func openAddLayerFlow(from controller: UIViewController) throws {
        guard let projectEditor = findProjectEditor() else {
            throw HandoffError.projectEditorNotFound
        }

        closeToolUI(from: controller, toward: projectEditor)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            do {
                try invokeAddLayer(on: projectEditor)
            } catch {
                ExtensionUI.alert(
                    title: "Rendered clip saved",
                    message: error.localizedDescription,
                    from: projectEditor
                )
            }
        }
    }

    private static func closeToolUI(from controller: UIViewController, toward projectEditor: UIViewController) {
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

    private static func invokeAddLayer(on controller: UIViewController) throws {
        let noArgument = NSSelectorFromString("addLayerTapped")
        if controller.responds(to: noArgument),
           methodAcceptsObjectCount(noArgument, on: controller, expected: 0) {
            _ = controller.perform(noArgument)
            return
        }

        let oneArgument = NSSelectorFromString("addLayerTapped:")
        if controller.responds(to: oneArgument),
           methodAcceptsObjectCount(oneArgument, on: controller, expected: 1) {
            _ = controller.perform(oneArgument, with: nil)
            return
        }

        throw HandoffError.addLayerActionUnavailable
    }

    private static func methodAcceptsObjectCount(
        _ selector: Selector,
        on object: NSObject,
        expected: UInt32
    ) -> Bool {
        guard let method = class_getInstanceMethod(type(of: object), selector) else { return false }
        return method_getNumberOfArguments(method) == expected + 2
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
