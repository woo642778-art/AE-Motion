#if canImport(UIKit)
import UIKit
import AEMotionExtensionsCore

@MainActor
enum PresetApplicationHostError: Error, LocalizedError {
    case sourceUnavailable
    case navigationUnavailable

    var errorDescription: String? {
        switch self {
        case .sourceUnavailable:
            return "The tool that opened Preset Studio is no longer available."
        case .navigationUnavailable:
            return "Preset Studio could not return to the source tool."
        }
    }
}

@MainActor
final class PresetApplicationContext {
    let candidate: PresetApplicationCandidate
    weak var sourceViewController: UIViewController?
    private let applyHandler: @MainActor (PresetDocument) throws -> Void

    init(
        candidate: PresetApplicationCandidate,
        sourceViewController: UIViewController,
        applyHandler: @escaping @MainActor (PresetDocument) throws -> Void
    ) {
        self.candidate = candidate
        self.sourceViewController = sourceViewController
        self.applyHandler = applyHandler
    }

    convenience init(
        targetID: String,
        title: String,
        adapterID: String,
        sourceViewController: UIViewController,
        applyHandler: @escaping @MainActor (PresetDocument) throws -> Void
    ) {
        self.init(
            candidate: .init(targetID: targetID, title: title, adapterID: adapterID),
            sourceViewController: sourceViewController,
            applyHandler: applyHandler
        )
    }

    func apply(_ document: PresetDocument) throws {
        guard sourceViewController != nil else {
            throw PresetApplicationHostError.sourceUnavailable
        }
        _ = try PresetApplicationResolver.resolve(
            document: document,
            requestedTarget: candidate.targetID
        )
        try applyHandler(document)
    }

    func returnToSource(from controller: UIViewController) throws {
        guard let sourceViewController else {
            throw PresetApplicationHostError.sourceUnavailable
        }
        guard let navigationController = controller.navigationController,
              navigationController.viewControllers.contains(where: { $0 === sourceViewController }) else {
            throw PresetApplicationHostError.navigationUnavailable
        }
        navigationController.popToViewController(sourceViewController, animated: true)
    }
}
#endif
