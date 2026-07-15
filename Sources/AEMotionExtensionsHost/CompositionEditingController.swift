#if canImport(UIKit)
import UIKit
import AEMotionExtensionsCore

@MainActor
final class CompositionEditingController: NSObject, TimelineMultiSelectionControllerDelegate {
    private let session: CompositionHostSession
    private weak var presenter: UIViewController?
    private lazy var multiSelectionController: TimelineMultiSelectionController = {
        let controller = TimelineMultiSelectionController(session: session, presenter: presenter!)
        controller.delegate = self
        return controller
    }()

    init(session: CompositionHostSession, presenter: UIViewController) {
        self.session = session
        self.presenter = presenter
        super.init()
    }

    func install() {
        guard presenter != nil else { return }
        multiSelectionController.install()
    }

    func uninstall() {
        multiSelectionController.uninstall()
    }

    @objc func presentInspectorForCurrentSelection() {
        guard let selected = compatibleCurrentSelection(), !selected.isEmpty else { return }
        presentInspector(selectedLayerIDs: selected, preferredSection: nil)
    }

    func timelineMultiSelectionController(
        _ controller: TimelineMultiSelectionController,
        didRequest action: TimelineSelectionAction,
        selectedLayerIDs: [UUID]
    ) {
        switch action {
        case .precompose:
            guard let controller = PrecomposeViewController(
                session: session,
                selectedLayerIDs: selectedLayerIDs
            ) else { return }
            present(controller)
        case .parent:
            presentInspector(selectedLayerIDs: selectedLayerIDs, preferredSection: .parent)
        case .matte:
            presentInspector(selectedLayerIDs: selectedLayerIDs, preferredSection: .matte)
        case .group:
            guard let controller = NullGroupViewController(
                session: session,
                selectedLayerIDs: selectedLayerIDs
            ) else { return }
            present(controller)
        }
    }

    private func presentInspector(
        selectedLayerIDs: [UUID],
        preferredSection: CompositionInspectorViewController.PreferredSection?
    ) {
        guard let controller = CompositionInspectorViewController(
            session: session,
            selectedLayerIDs: selectedLayerIDs,
            preferredSection: preferredSection
        ) else { return }
        present(controller)
    }

    private func compatibleCurrentSelection() -> [UUID]? {
        guard let snapshot = session.adapter.snapshot() else { return nil }
        let compatible = Set(snapshot.layers.filter { $0.isCompatible && !$0.isLocked }.map(\.id))
        let selected = snapshot.selectedLayerIDs.filter { compatible.contains($0) }
        guard selected.count == snapshot.selectedLayerIDs.count else { return nil }
        return selected
    }

    private func present(_ controller: UIViewController) {
        guard let presenter, presenter.presentedViewController == nil else { return }
        let navigation = UINavigationController(rootViewController: controller)
        navigation.modalPresentationStyle = .pageSheet
        if let sheet = navigation.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        presenter.present(navigation, animated: true)
    }
}
#endif
