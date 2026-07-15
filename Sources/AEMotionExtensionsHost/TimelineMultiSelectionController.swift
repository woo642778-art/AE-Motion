#if canImport(UIKit)
import UIKit
import AEMotionExtensionsCore

@MainActor
enum TimelineSelectionAction: String, Sendable {
    case precompose
    case parent
    case matte
    case group
}

@MainActor
protocol TimelineMultiSelectionControllerDelegate: AnyObject {
    func timelineMultiSelectionController(
        _ controller: TimelineMultiSelectionController,
        didRequest action: TimelineSelectionAction,
        selectedLayerIDs: [UUID]
    )
}

struct TimelineSelectionState: Equatable, Sendable {
    var selectionIdentity: String
    var selectedLayerIDs: [UUID]
    var selectedStart: Double?
    var selectedEnd: Double?
    var isActive: Bool

    var canPrecompose: Bool { isActive && selectedLayerIDs.count >= 2 }
    var selectedDuration: Double? {
        guard let selectedStart, let selectedEnd else { return nil }
        return max(0, selectedEnd - selectedStart)
    }
}

@MainActor
final class TimelineMultiSelectionController: NSObject, UIGestureRecognizerDelegate {
    weak var delegate: TimelineMultiSelectionControllerDelegate?

    private let session: CompositionHostSession
    private weak var presenter: UIViewController?
    private var state = TimelineSelectionState(
        selectionIdentity: "",
        selectedLayerIDs: [],
        selectedStart: nil,
        selectedEnd: nil,
        isActive: false
    )
    private lazy var longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
    private lazy var selectionTap = UITapGestureRecognizer(target: self, action: #selector(handleSelectionTap(_:)))
    private let actionBar = UIView()
    private let countLabel = UILabel()
    private let precomposeButton = UIButton(type: .system)
    private let selectionOverlay = UIView()

    init(session: CompositionHostSession, presenter: UIViewController) {
        self.session = session
        self.presenter = presenter
        super.init()
        configureGestures()
        configureSelectionOverlay()
        configureActionBar()
    }

    func install() {
        guard session.adapter.verifiedCapabilities.contains(.mutateSelection) else { return }
        session.timelineView.addGestureRecognizer(longPress)
        session.timelineView.addGestureRecognizer(selectionTap)
        selectionTap.isEnabled = false
    }

    func uninstall() {
        session.timelineView.removeGestureRecognizer(longPress)
        session.timelineView.removeGestureRecognizer(selectionTap)
        exitSelectionMode(clearHostSelection: false)
    }

    private func configureGestures() {
        longPress.minimumPressDuration = 0.35
        longPress.cancelsTouchesInView = true
        longPress.delegate = self
        selectionTap.cancelsTouchesInView = true
        selectionTap.delegate = self
    }

    private func configureSelectionOverlay() {
        selectionOverlay.frame = session.timelineView.bounds
        selectionOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        selectionOverlay.isUserInteractionEnabled = false
        selectionOverlay.backgroundColor = .clear
        selectionOverlay.accessibilityIdentifier = "aemotion.timeline.selection-overlay"
    }

    private func configureActionBar() {
        guard let presenter else { return }
        actionBar.translatesAutoresizingMaskIntoConstraints = false
        actionBar.backgroundColor = .secondarySystemBackground
        actionBar.layer.cornerRadius = 14
        actionBar.layer.cornerCurve = .continuous
        actionBar.isHidden = true
        actionBar.accessibilityIdentifier = "aemotion.timeline.multi-select-bar"

        countLabel.font = .preferredFont(forTextStyle: .caption1)
        countLabel.adjustsFontForContentSizeCategory = true
        countLabel.setContentHuggingPriority(.required, for: .horizontal)

        configureButton(precomposeButton, title: "Pre-compose", image: "square.stack.3d.up", action: #selector(requestPrecompose))
        let parent = makeButton(title: "Parent", image: "arrow.triangle.branch", action: #selector(requestParent))
        let matte = makeButton(title: "Matte", image: "circle.lefthalf.filled", action: #selector(requestMatte))
        let group = makeButton(title: "Group", image: "rectangle.3.group", action: #selector(requestGroup))
        let close = makeButton(title: "Done", image: "checkmark", action: #selector(closeSelection))

        let stack = UIStackView(arrangedSubviews: [countLabel, precomposeButton, parent, matte, group, close])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 8
        stack.distribution = .fillProportionally
        actionBar.addSubview(stack)
        presenter.view.addSubview(actionBar)

        NSLayoutConstraint.activate([
            actionBar.leadingAnchor.constraint(greaterThanOrEqualTo: presenter.view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            actionBar.trailingAnchor.constraint(lessThanOrEqualTo: presenter.view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            actionBar.centerXAnchor.constraint(equalTo: presenter.view.safeAreaLayoutGuide.centerXAnchor),
            actionBar.bottomAnchor.constraint(equalTo: presenter.view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            stack.leadingAnchor.constraint(equalTo: actionBar.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: actionBar.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: actionBar.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: actionBar.bottomAnchor, constant: -8),
        ])
    }

    private func configureButton(_ button: UIButton, title: String, image: String, action: Selector) {
        button.setTitle(title, for: .normal)
        button.setImage(UIImage(systemName: image), for: .normal)
        button.addTarget(self, action: action, for: .touchUpInside)
        button.titleLabel?.font = .preferredFont(forTextStyle: .caption1)
    }

    private func makeButton(title: String, image: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        configureButton(button, title: title, image: image, action: action)
        return button
    }

    @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began,
              let layerID = layerID(at: recognizer.location(in: session.timelineView)) else { return }
        enterSelectionMode(startingWith: layerID)
    }

    @objc private func handleSelectionTap(_ recognizer: UITapGestureRecognizer) {
        guard state.isActive,
              let layerID = layerID(at: recognizer.location(in: session.timelineView)) else { return }
        toggle(layerID)
    }

    private func layerID(at point: CGPoint) -> UUID? {
        guard let snapshot = session.adapter.snapshot() else { return nil }
        return snapshot.layers.first(where: {
            $0.isCompatible && !$0.isLocked && ($0.timelineFrame?.contains(point) == true)
        })?.id
    }

    private func enterSelectionMode(startingWith layerID: UUID) {
        guard let snapshot = session.adapter.snapshot(),
              session.adapter.setSelectedLayerIDs([layerID]) else { return }
        state = TimelineSelectionState(
            selectionIdentity: snapshot.selectionIdentity,
            selectedLayerIDs: [layerID],
            selectedStart: nil,
            selectedEnd: nil,
            isActive: true
        )
        selectionTap.isEnabled = true
        actionBar.isHidden = false
        if selectionOverlay.superview == nil { session.timelineView.addSubview(selectionOverlay) }
        refreshStateAndUI()
    }

    private func toggle(_ layerID: UUID) {
        var selected = state.selectedLayerIDs
        if let index = selected.firstIndex(of: layerID) {
            selected.remove(at: index)
        } else {
            selected.append(layerID)
        }
        guard !selected.isEmpty else {
            exitSelectionMode(clearHostSelection: true)
            return
        }
        guard session.adapter.setSelectedLayerIDs(selected) else {
            exitSelectionMode(clearHostSelection: false)
            return
        }
        state.selectedLayerIDs = selected
        refreshStateAndUI()
    }

    private func refreshStateAndUI() {
        guard let snapshot = session.adapter.snapshot(),
              let document = session.adapter.readCompositionDocument(),
              let composition = document.compositions.first(where: { $0.id == snapshot.compositionID }) else {
            exitSelectionMode(clearHostSelection: false)
            return
        }
        let selectedSet = Set(state.selectedLayerIDs)
        let layers = composition.layers.filter { selectedSet.contains($0.id) }
        state.selectionIdentity = snapshot.selectionIdentity
        state.selectedStart = layers.map(\.timeRange.start).min()
        state.selectedEnd = layers.map(\.timeRange.end).max()
        precomposeButton.isEnabled = state.canPrecompose
        let duration = state.selectedDuration.map { String(format: " · %.2fs", $0) } ?? ""
        countLabel.text = "\(state.selectedLayerIDs.count) selected\(duration)"
        redrawSelectionIndicators(using: snapshot)
    }

    private func redrawSelectionIndicators(using snapshot: HostCompositionSnapshot) {
        selectionOverlay.subviews.forEach { $0.removeFromSuperview() }
        let selected = Set(state.selectedLayerIDs)
        for handle in snapshot.layers where selected.contains(handle.id) {
            guard let frame = handle.timelineFrame else { continue }
            let badge = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
            badge.tintColor = .systemBlue
            badge.frame = CGRect(x: frame.x + 6, y: frame.y + 6, width: 22, height: 22)
            badge.accessibilityIdentifier = "aemotion.timeline.selected.\(handle.id.uuidString)"
            selectionOverlay.addSubview(badge)
        }
    }

    @objc private func requestPrecompose() { request(.precompose) }
    @objc private func requestParent() { request(.parent) }
    @objc private func requestMatte() { request(.matte) }
    @objc private func requestGroup() { request(.group) }
    @objc private func closeSelection() { exitSelectionMode(clearHostSelection: false) }

    private func request(_ action: TimelineSelectionAction) {
        guard state.isActive else { return }
        if action == .precompose, !state.canPrecompose { return }
        delegate?.timelineMultiSelectionController(self, didRequest: action, selectedLayerIDs: state.selectedLayerIDs)
    }

    private func exitSelectionMode(clearHostSelection: Bool) {
        if clearHostSelection { _ = session.adapter.setSelectedLayerIDs([]) }
        state.isActive = false
        state.selectedLayerIDs = []
        selectionTap.isEnabled = false
        actionBar.isHidden = true
        selectionOverlay.removeFromSuperview()
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        false
    }
}
#endif
