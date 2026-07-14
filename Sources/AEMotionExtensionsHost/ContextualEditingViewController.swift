#if canImport(UIKit)
import UIKit
import AEMotionExtensionsCore

@MainActor
final class ContextualEditingViewController: UIViewController {
    private let adapter: HostControlMutationAdapter
    private let descriptor: ContextualToolDescriptor
    private weak var hostController: UIViewController?
    private let coordinator = LivePreviewCoordinator()
    private var values: [Float]
    private var completed = false
    private var selectionTimer: Timer?
    private let stack = UIStackView()

    init(adapter: HostControlMutationAdapter, descriptor: ContextualToolDescriptor, hostController: UIViewController) {
        self.adapter = adapter
        self.descriptor = descriptor
        self.hostController = hostController
        self.values = adapter.snapshot()
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = descriptor.title
        AEMotionTheme.apply(to: self)
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Cancel",
            style: .plain,
            target: self,
            action: #selector(cancelChanges)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Done",
            style: .done,
            target: self,
            action: #selector(commitChanges)
        )

        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 18),
        ])

        let status = UILabel()
        status.text = "Changes update the current preview immediately. Cancel restores the original values."
        status.numberOfLines = 0
        status.font = .preferredFont(forTextStyle: .footnote)
        status.textColor = AEMotionTheme.secondaryText
        stack.addArrangedSubview(status)

        for (index, range) in adapter.ranges.enumerated() {
            let label = UILabel()
            label.text = "Parameter \(index + 1)"
            label.font = .preferredFont(forTextStyle: .subheadline)
            label.textColor = AEMotionTheme.primaryText
            let slider = UISlider()
            slider.tag = index
            slider.minimumValue = range.lowerBound
            slider.maximumValue = range.upperBound
            slider.value = values[index]
            slider.addTarget(self, action: #selector(sliderChanged(_:)), for: .valueChanged)
            let row = UIStackView(arrangedSubviews: [label, slider])
            row.axis = .vertical
            row.spacing = 6
            stack.addArrangedSubview(row)
        }

        addContextSpecificControls()
        do {
            try coordinator.begin(adapter: adapter)
        } catch {
            navigationItem.rightBarButtonItem?.isEnabled = false
            status.text = "Live preview is unavailable for this host panel."
        }
        startSelectionMonitoring()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        selectionTimer?.invalidate()
        selectionTimer = nil
        if !completed { coordinator.cancel() }
    }

    @objc private func sliderChanged(_ sender: UISlider) {
        guard values.indices.contains(sender.tag) else { return }
        values[sender.tag] = sender.value
        coordinator.update(values)
    }

    @objc private func commitChanges() {
        completed = true
        coordinator.commit()
        dismiss(animated: true)
    }

    @objc private func cancelChanges() {
        completed = true
        coordinator.cancel()
        dismiss(animated: true)
    }

    private func addContextSpecificControls() {
        switch descriptor.context {
        case .transform:
            let pad = UIView()
            pad.backgroundColor = AEMotionTheme.surface
            pad.layer.cornerRadius = 12
            pad.heightAnchor.constraint(equalToConstant: 120).isActive = true
            let hint = UILabel()
            hint.text = "Drag to adjust the first two transform controls"
            hint.textAlignment = .center
            hint.textColor = AEMotionTheme.secondaryText
            hint.font = .preferredFont(forTextStyle: .caption1)
            hint.translatesAutoresizingMaskIntoConstraints = false
            pad.addSubview(hint)
            NSLayoutConstraint.activate([
                hint.centerXAnchor.constraint(equalTo: pad.centerXAnchor),
                hint.centerYAnchor.constraint(equalTo: pad.centerYAnchor),
            ])
            pad.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(handleTransformPan(_:))))
            stack.addArrangedSubview(pad)
        case .speed:
            let freeze = UIButton(type: .system)
            freeze.setTitle("Freeze", for: .normal)
            freeze.addTarget(self, action: #selector(applyFreeze), for: .touchUpInside)
            freeze.isEnabled = adapter.ranges.first.map { $0.contains(0) } ?? false
            let reverse = UIButton(type: .system)
            reverse.setTitle("Reverse", for: .normal)
            reverse.addTarget(self, action: #selector(applyReverse), for: .touchUpInside)
            reverse.isEnabled = adapter.ranges.first.map { $0.lowerBound < 0 } ?? false
            AEMotionTheme.style(secondary: freeze)
            AEMotionTheme.style(secondary: reverse)
            let row = UIStackView(arrangedSubviews: [freeze, reverse])
            row.axis = .horizontal
            row.distribution = .fillEqually
            row.spacing = 10
            stack.addArrangedSubview(row)
        case .graph:
            let note = UILabel()
            note.text = "Graph controls are attached only to host panels exposing compatible value sliders."
            note.numberOfLines = 0
            note.font = .preferredFont(forTextStyle: .caption1)
            note.textColor = AEMotionTheme.secondaryText
            stack.addArrangedSubview(note)
        case .effect:
            break
        }
    }

    @objc private func handleTransformPan(_ recognizer: UIPanGestureRecognizer) {
        guard values.count >= 2 else { return }
        let delta = recognizer.translation(in: recognizer.view)
        recognizer.setTranslation(.zero, in: recognizer.view)
        let ranges = adapter.ranges
        let xSpan = ranges[0].upperBound - ranges[0].lowerBound
        let ySpan = ranges[1].upperBound - ranges[1].lowerBound
        values[0] = min(max(values[0] + Float(delta.x / 240) * xSpan, ranges[0].lowerBound), ranges[0].upperBound)
        values[1] = min(max(values[1] + Float(delta.y / 240) * ySpan, ranges[1].lowerBound), ranges[1].upperBound)
        coordinator.update(values)
        syncSliderValues()
    }

    @objc private func applyFreeze() {
        guard !values.isEmpty, adapter.ranges[0].contains(0) else { return }
        values[0] = 0
        coordinator.update(values)
        syncSliderValues()
    }

    @objc private func applyReverse() {
        guard !values.isEmpty, adapter.ranges[0].lowerBound < 0 else { return }
        values[0] = max(adapter.ranges[0].lowerBound, -abs(values[0] == 0 ? 1 : values[0]))
        coordinator.update(values)
        syncSliderValues()
    }

    private func syncSliderValues() {
        for case let slider as UISlider in stack.arrangedSubviews.flatMap({ $0.subviews + [$0] }) {
            if values.indices.contains(slider.tag) { slider.value = values[slider.tag] }
        }
    }

    private func startSelectionMonitoring() {
        selectionTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let hostController = self.hostController else { return }
                guard let current = HostEditingContextBridge.resolve(context: self.descriptor.context, in: hostController) else {
                    self.coordinator.selectionDidChange(to: ObjectIdentifier(hostController))
                    return
                }
                self.coordinator.selectionDidChange(to: current.adapter.selectionIdentity)
            }
        }
    }
}
#endif
