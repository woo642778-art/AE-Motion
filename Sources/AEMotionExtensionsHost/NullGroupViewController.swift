#if canImport(UIKit)
import UIKit
import AEMotionExtensionsCore

@MainActor
final class NullGroupViewController: UIViewController, UITextFieldDelegate {
    private let session: CompositionHostSession
    private let selectedLayerIDs: [UUID]
    private let compositionID: UUID
    private let initialDocument: CompositionDocument
    private let coordinator = CompositionLivePreviewCoordinator()
    private let nameField = UITextField()
    private let summaryLabel = UILabel()
    private let statusLabel = UILabel()
    private var latestResult: NullGroupResult?
    private var didCommit = false

    init?(session: CompositionHostSession, selectedLayerIDs: [UUID]) {
        guard !selectedLayerIDs.isEmpty,
              session.adapter.verifiedCapabilities.contains(.structuralParenting),
              session.adapter.verifiedCapabilities.contains(.previewComposition),
              let snapshot = session.adapter.snapshot(),
              let document = session.adapter.readCompositionDocument() else { return nil }
        self.session = session
        self.selectedLayerIDs = selectedLayerIDs
        self.compositionID = snapshot.compositionID
        self.initialDocument = document
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Create Null Group"
        view.backgroundColor = .systemGroupedBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Cancel",
            style: .plain,
            target: self,
            action: #selector(cancel)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Done",
            style: .done,
            target: self,
            action: #selector(done)
        )
        configureForm()
        do {
            try coordinator.begin(session: session)
            rebuildPreview()
        } catch {
            setUnavailable("Live preview is unavailable for this host state.")
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if !didCommit { coordinator.cancel(reason: .userCancelled) }
    }

    private func configureForm() {
        nameField.borderStyle = .roundedRect
        nameField.text = suggestedName()
        nameField.placeholder = "Null name"
        nameField.delegate = self
        nameField.addTarget(self, action: #selector(nameChanged), for: .editingChanged)
        nameField.accessibilityIdentifier = "aemotion.null-group.name"

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
        let names = initialDocument.compositions
            .first(where: { $0.id == compositionID })?
            .layers.map(\.name) ?? []
        var index = 1
        while names.contains("Null Group \(index)") { index += 1 }
        return "Null Group \(index)"
    }

    @objc private func nameChanged() {
        rebuildPreview()
    }

    private func rebuildPreview() {
        guard coordinator.isActive else { return }
        do {
            let result = try NullGroupEngine.group(
                document: initialDocument,
                request: .init(
                    compositionID: compositionID,
                    selectedLayerIDs: selectedLayerIDs,
                    name: nameField.text ?? ""
                )
            )
            latestResult = result
            coordinator.update(result.document)
            summaryLabel.text = "\(selectedLayerIDs.count) layers · Null at selection center · \(String(format: "%.2f", result.nullLayer.timeRange.duration))s"
            statusLabel.text = "World position, rotation, scale, anchor, skew and opacity are preserved in the live preview."
            navigationItem.rightBarButtonItem?.isEnabled = true
        } catch {
            latestResult = nil
            setUnavailable("This selection cannot be grouped safely.")
        }
    }

    private func setUnavailable(_ message: String) {
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
                label: "Create Null Group",
                affectedCompositionID: self.compositionID
            )
            if committed {
                self.didCommit = true
                self.dismiss(animated: true)
            } else {
                self.setUnavailable("The host rejected the Null group. The original layer graph was restored.")
            }
        }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}
#endif
