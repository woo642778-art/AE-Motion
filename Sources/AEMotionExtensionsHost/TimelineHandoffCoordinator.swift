#if canImport(UIKit) && canImport(Photos)
import UIKit
import Photos

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

    /// Saves the rendered file to Photos on a nonisolated callback path, then returns
    /// to the active project editor on the main actor.
    ///
    /// Photos invokes its completion handlers on a private serial queue. Those callbacks
    /// must not inherit MainActor isolation or Swift 6 will terminate with
    /// _dispatch_assert_queue_fail immediately after the save reaches 100%.
    static func renderResultReady(
        fileURL: URL,
        from controller: UIViewController,
        completion: @escaping @MainActor @Sendable (Result<Void, HandoffError>) -> Void
    ) {
        Task { @MainActor [weak controller] in
            let saveResult = await saveVideoToPhotos(fileURL: fileURL)

            switch saveResult {
            case .failure(let error):
                completion(.failure(error))

            case .success:
                RenderTemporaryFiles.remove(fileURL)
                guard let controller else {
                    completion(.failure(.projectEditorNotFound))
                    return
                }
                guard let projectEditor = findProjectEditor() else {
                    completion(.failure(.projectEditorNotFound))
                    return
                }

                completion(.success(()))

                // Keep all UIKit navigation on the main actor. Deferring one turn also
                // lets the caller finish its status/progress update before the tool closes.
                await Task.yield()
                closeToolUI(from: controller, toward: projectEditor)
            }
        }
    }

    /// Performs authorization and Photos saving without actor inheritance.
    /// The Photos callbacks may execute on com.apple.PHPhotoLibrary.changes.
    private nonisolated static func saveVideoToPhotos(
        fileURL: URL
    ) async -> Result<Void, HandoffError> {
        let authorization = await requestAddAuthorization()
        if case .failure = authorization {
            return authorization
        }

        return await withCheckedContinuation {
            (continuation: CheckedContinuation<Result<Void, HandoffError>, Never>) in

            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
            }) { success, error in
                if success {
                    continuation.resume(returning: .success(()))
                } else {
                    continuation.resume(returning: .failure(.photoSaveFailed(
                        error?.localizedDescription
                            ?? "Could not save the rendered clip to Photos."
                    )))
                }
            }
        }
    }

    /// Requests Photos add-only permission from a nonisolated context so the Photos
    /// framework can call its completion block on any queue without violating MainActor.
    private nonisolated static func requestAddAuthorization(
    ) async -> Result<Void, HandoffError> {
        let current = PHPhotoLibrary.authorizationStatus(for: .addOnly)

        if current == .authorized || current == .limited {
            return .success(())
        }
        if current == .denied || current == .restricted {
            return .failure(.photoPermissionDenied)
        }

        return await withCheckedContinuation {
            (continuation: CheckedContinuation<Result<Void, HandoffError>, Never>) in

            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                if status == .authorized || status == .limited {
                    continuation.resume(returning: .success(()))
                } else {
                    continuation.resume(returning: .failure(.photoPermissionDenied))
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
                if let match = findProjectEditor(in: child, visited: &visited) {
                    return match
                }
            }
        }

        if let tab = controller as? UITabBarController {
            for child in (tab.viewControllers ?? []).reversed() {
                if let match = findProjectEditor(in: child, visited: &visited) {
                    return match
                }
            }
        }

        for child in controller.children.reversed() {
            if let match = findProjectEditor(in: child, visited: &visited) {
                return match
            }
        }

        return nil
    }
}
#endif
