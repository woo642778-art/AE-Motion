#if canImport(UIKit)
import UIKit
import AEMotionExtensionsCore

@MainActor
final class PrecomposeViewController: UIViewController, UITextFieldDelegate {
    private let session: CompositionHostSession
    private let selectedLayerIDs: [UUID]
    private let coordinator: CompositionLivePreviewCoordinator
    private let initialDocument: CompositionDocument
    private let compositionID: UUID
    private let nameField = UITextField()
    private let summaryLabel = UILabel()
    private let statusLabel = UILabel()
    private var latestResult: PrecomposeResult?
    private var didCommit = false

    init?(session: CompositionHostSession, selectedLayerIDs: [UUID]) {
        guard selectedLayerIDs.count >= 2,
              session.adapter.verifiedCapabilities.contains(.structuralPrecompose),
              session.adapter.verifiedCapabilities.contains(.previewComposition),
              let snapshot = session.adapter.snapshot(),
              let document = session.adapter.readCompositionDocument() else { return nil }
        self.session = session
        self.selectedLayerIDs = selectedLayerIDs
        self.coordinator = CompositionLivePreviewCoordinator()
        self.initialDocument = document
        self.compositionID = snapshot.compositionID
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Pre-compose"
        view.backgroundColor = .systemGroupedBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Cancel", style: .plain, target: self, action: #selector(cancel))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(done))
        configureForm()
        do {
            try coordinator.begin(session: session)
            rebuildPreview()
        } catch {
            setUnavailable(message: "Live preview is unavailable for this host state.")
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if !didCommit { coordinator.cancel(reason: .userCancelled) }
    }

    private func configureForm() {
        nameField.borderStyle = .roundedRect
        nameField.placeholder = "Pre-comp name"
        nameField.text = suggestedName()
        nameField.delegate = self
        nameField.addTarget(self, action: #selector(nameChanged), for: .editingChanged)
        nameField.accessibilityIdentifier = "aemotion.precompose.name"

        summaryLabel.numberOfLines = 0
        summaryLabel.font = .preferredFont(forTextStyle: .body)
        statusLabel.numberOfLines = 0
        statusLabel.font = .preferredFont(forTextStyle: .footnote)
        statusLabel.textColor = .secondaryLabel

        let stack = UIStackView(arrangedSubviews: [nameField, summaryLabel, statusLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 14
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
        ])
    }

    private func suggestedName() -> String {
        let existing = initialDocument.compositions.map(\.name)
        var index = 1
        while existing.contains("Pre-comp \(index)") { index += 1 }
        return "Pre-comp \(index)"
    }

    @objc private func nameChanged() {
        rebuildPreview()
    }

    private func rebuildPreview() {
        guard coordinator.isActive else { return }
        do {
            let result = try PrecomposeEngine.precompose(
                document: initialDocument,
                request: .init(
                    compositionID: compositionID,
                    selectedLayerIDs: selectedLayerIDs,
                    name: nameField.text ?? ""
                )
            )
            latestResult = result
            coordinator.update(result.document)
            summaryLabel.text = "\(selectedLayerIDs.count) layers · \(String(format: "%.2f", result.childComposition.duration))s"
            statusLabel.text = "The editable child composition is shown in the viewer in real time."
            navigationItem.rightBarButtonItem?.isEnabled = true
        } catch let error as PrecomposeError {
            latestResult = nil
            navigationItem.rightBarButtonItem?.isEnabled = false
            switch error {
            case .relationshipCrossesSelectionBoundary:
                statusLabel.text = "Select linked Parent and Track Matte layers together before pre-composing."
            case .requiresAtLeastTwoLayers:
                statusLabel.text = "Select at least two layers."
            default:
                statusLabel.text = "This selection cannot be pre-composed safely."
            }
        } catch {
            setUnavailable(message: "This selection cannot be previewed.")
        }
    }

    private func setUnavailable(message: String) {
        statusLabel.text = message
        navigationItem.rightBarButtonItem?.isEnabled = false
    }

    @objc private func cancel() {
        coordinator.cancel(reason: .userCancelled)
        dismiss(animated: true)
    }

    @objc private func done() {
        guard latestResult != nil else { return }
        navigationItem.rightBarButtonItem?.isEnabled = false
        Task { @MainActor [weak self] in
            guard let self else { return }
            let committed = await self.coordinator.commit(
                label: "Pre-compose",
                affectedCompositionID: self.compositionID
            )
            if committed {
                self.didCommit = true
                self.dismiss(animated: true)
            } else {
                self.setUnavailable(message: "The host did not confirm the Pre-compose result. The original timeline was restored.")
            }
        }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}
#endif
