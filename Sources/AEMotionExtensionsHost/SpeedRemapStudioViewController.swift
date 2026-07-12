#if canImport(UIKit) && canImport(AVFoundation) && canImport(UniformTypeIdentifiers) && canImport(PhotosUI)
import UIKit
import AVFoundation
import UniformTypeIdentifiers
import PhotosUI
import AEMotionExtensionsCore

@MainActor
final class SpeedRemapStudioViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let preview = VideoPreviewPanel()
    private let sourceLabel = ExtensionUI.label("No source video selected.")
    private let fpsField = ExtensionUI.field("Output FPS", value: "30")
    private let curveEditor = InteractiveCurveEditorView()
    private let table = UITableView(frame: .zero, style: .insetGrouped)
    private let progress = UIProgressView(progressViewStyle: .default)
    private let status = ExtensionUI.label("1× normal · 0 freeze · negative reverse")
    private let includeAudioSwitch = UISwitch()
    private let preservePitchSwitch = UISwitch()
    private weak var pageScrollView: UIScrollView?

    private var picker: MediaSourcePicker?
    private var sourceURL: URL?
    private var sourceDuration: Double = 3
    private var isSyncingEditor = false
    private var keyframes: [SpeedKeyframe] = [
        .init(outputTime: 0, velocity: 1, incomingSlope: 0, outgoingSlope: 0),
        .init(outputTime: 3, velocity: 1, incomingSlope: 0, outgoingSlope: 0),
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Speed Remap Studio"
        view.backgroundColor = .systemBackground

        includeAudioSwitch.isOn = true
        preservePitchSwitch.isOn = true

        curveEditor.heightAnchor.constraint(equalToConstant: 300).isActive = true
        curveEditor.minimumPointCount = 2
        curveEditor.horizontalZero = 0
        curveEditor.lockFirstX = true
        curveEditor.lockLastX = true
        curveEditor.onChange = { [weak self] points in self?.editorChanged(points) }
        curveEditor.onSelectionChange = { [weak self] point in
            guard let self else { return }
            if let point {
                self.status.text = "Selected: \(String(format: "%.3f", point.x)) s · \(String(format: "%.3f", point.y))×"
            }
        }
        curveEditor.onInteractionChanged = { [weak self] interacting in
            self?.setPageScrollingEnabled(!interacting)
        }

        table.dataSource = self
        table.delegate = self
        table.register(UITableViewCell.self, forCellReuseIdentifier: "keyframe")
        table.heightAnchor.constraint(equalToConstant: 240).isActive = true
        progress.progress = 0

        let photos = ExtensionUI.button("Choose from Photos", action: UIAction { [weak self] _ in self?.chooseVideo(photos: true) })
        let files = ExtensionUI.secondaryButton("Choose from Files", action: UIAction { [weak self] _ in self?.chooseVideo(photos: false) })
        let pickerRow = ExtensionUI.horizontalStack([photos, files])

        let add = ExtensionUI.secondaryButton("Add Keyframe", action: UIAction { [weak self] _ in
            guard let self else { return }
            let time = self.preview.duration > 0 ? self.preview.currentTime : self.sourceDuration * 0.5
            self.addKeyframe(at: time)
        })
        let delete = ExtensionUI.secondaryButton("Delete Selected", action: UIAction { [weak self] _ in
            self?.curveEditor.deleteSelectedPoint()
        })
        let editRow = ExtensionUI.horizontalStack([add, delete])

        let export = ExtensionUI.secondaryButton("Export Retimed Video", action: UIAction { [weak self] action in
            self?.renderVideo(addToTimeline: false, sourceView: action.sender as? UIView)
        })
        let addToTimeline = ExtensionUI.button("Render & Open Add Layer", action: UIAction { [weak self] action in
            self?.renderVideo(addToTimeline: true, sourceView: action.sender as? UIView)
        })
        let renderActions = ExtensionUI.horizontalStack([export, addToTimeline])
        let shareCurve = ExtensionUI.secondaryButton("Share Speed Curve JSON", action: UIAction { [weak self] action in
            self?.shareCurve(sourceView: action.sender as? UIView)
        })

        pageScrollView = ExtensionUI.installScrollStack(ExtensionUI.stack([
            ExtensionUI.label("Watch the source while editing. Drag blue points and orange tangent handles. Double-tap the graph to add a point."),
            preview,
            pickerRow,
            sourceLabel,
            ExtensionUI.label("Flow-style presets", style: .headline),
            makePresetScroller(),
            curveEditor,
            editRow,
            fpsField,
            ExtensionUI.labeledSwitch("Include retimed audio", control: includeAudioSwitch),
            ExtensionUI.labeledSwitch("Preserve audio pitch", control: preservePitchSwitch),
            table,
            status,
            progress,
            renderActions,
            shareCurve,
            ExtensionUI.label("Curve editing locks page scrolling while a point or tangent is dragged. Render & Open Add Layer saves the result as the newest Photos clip and opens Alight Motion's Add Layer flow. Forward audio segments use spectral pitch preservation; freeze and reverse sections remain silent.", style: .footnote),
        ]), in: self)
        refresh()
    }

    private func makePresetScroller() -> UIView {
        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        let presets = ["Normal", "Smooth Ramp", "Impact", "Freeze Hit", "Reverse", "Velocity Punch"]
        for name in presets {
            let button = ExtensionUI.secondaryButton(name, action: UIAction { [weak self] _ in self?.applyPreset(name) })
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 105).isActive = true
            stack.addArrangedSubview(button)
        }
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
            scroll.heightAnchor.constraint(equalToConstant: 44),
        ])
        return scroll
    }

    private func chooseVideo(photos: Bool) {
        let picker = MediaSourcePicker(presenter: self) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let url): self.loadSource(url)
            case .failure(let error):
                ExtensionUI.alert(title: "Import failed", message: error.localizedDescription, from: self)
            }
        }
        self.picker = picker
        photos ? picker.presentPhotos() : picker.presentFiles()
    }

    private func loadSource(_ url: URL) {
        sourceURL = url
        preview.load(url: url)
        let asset = AVURLAsset(url: url)
        let duration = asset.duration.seconds
        sourceDuration = duration.isFinite ? max(0.1, duration) : 3
        keyframes = [
            .init(outputTime: 0, velocity: 1, incomingSlope: 0, outgoingSlope: 0),
            .init(outputTime: sourceDuration, velocity: 1, incomingSlope: 0, outgoingSlope: 0),
        ]
        sourceLabel.text = "\(url.lastPathComponent)\nSource duration: \(String(format: "%.3f", sourceDuration)) s"
        refresh()
    }

    private func applyPreset(_ name: String) {
        let duration = max(0.5, sourceDuration)
        switch name {
        case "Smooth Ramp": keyframes = SpeedRemapPreset.smoothRamp(duration: duration)
        case "Impact": keyframes = SpeedRemapPreset.impact(duration: duration)
        case "Freeze Hit": keyframes = SpeedRemapPreset.freezeHit(duration: duration)
        case "Reverse":
            keyframes = [
                .init(outputTime: 0, velocity: -1, incomingSlope: 0, outgoingSlope: 0),
                .init(outputTime: duration, velocity: -1, incomingSlope: 0, outgoingSlope: 0),
            ]
        case "Velocity Punch":
            keyframes = [
                .init(outputTime: 0, velocity: 1, outgoingSlope: -5),
                .init(outputTime: duration * 0.22, velocity: 0.15, incomingSlope: 0, outgoingSlope: 12),
                .init(outputTime: duration * 0.38, velocity: 4.5, incomingSlope: 0, outgoingSlope: -7),
                .init(outputTime: duration * 0.62, velocity: 0.65, incomingSlope: 0, outgoingSlope: 1.2),
                .init(outputTime: duration, velocity: 1, incomingSlope: 0),
            ]
        default:
            keyframes = [
                .init(outputTime: 0, velocity: 1, incomingSlope: 0, outgoingSlope: 0),
                .init(outputTime: duration, velocity: 1, incomingSlope: 0, outgoingSlope: 0),
            ]
        }
        refresh()
    }

    private func addKeyframe(at time: Double) {
        let clamped = min(max(0.001, time), max(0.002, sourceDuration - 0.001))
        if keyframes.contains(where: { abs($0.outputTime - clamped) < 0.0005 }) { return }
        let velocity = (try? curve().velocity(at: clamped)) ?? 1
        keyframes.append(.init(outputTime: clamped, velocity: velocity, incomingSlope: 0, outgoingSlope: 0))
        refresh()
    }

    private func curve() throws -> SpeedCurve {
        let reverseOnly = keyframes.allSatisfy { $0.velocity < 0 }
        return try SpeedCurve(sourceOrigin: reverseOnly ? sourceDuration : 0, keyframes: keyframes)
    }

    private func editorChanged(_ points: [EditableCurvePoint]) {
        guard !isSyncingEditor else { return }
        keyframes = points.map {
            SpeedKeyframe(
                id: $0.id,
                outputTime: $0.x,
                velocity: $0.y,
                incomingSlope: $0.incomingSlope,
                outgoingSlope: $0.outgoingSlope
            )
        }.sorted { $0.outputTime < $1.outputTime }
        table.reloadData()
        updateStatus()
    }

    private func refresh() {
        keyframes.sort { $0.outputTime < $1.outputTime }
        table.reloadData()
        let velocities = keyframes.map(\.velocity)
        let minVelocity = min(-1, (velocities.min() ?? 0) - 0.5)
        let maxVelocity = max(2, (velocities.max() ?? 1) + 0.5)
        curveEditor.xDomain = 0...max(0.1, keyframes.last?.outputTime ?? sourceDuration)
        curveEditor.yDomain = minVelocity...maxVelocity
        curveEditor.horizontalZero = 0
        isSyncingEditor = true
        curveEditor.setPoints(keyframes.map {
            EditableCurvePoint(
                id: $0.id,
                x: $0.outputTime,
                y: $0.velocity,
                incomingSlope: $0.incomingSlope,
                outgoingSlope: $0.outgoingSlope
            )
        })
        isSyncingEditor = false
        updateStatus()
    }

    private func updateStatus() {
        do {
            let curve = try curve()
            let samples = (0...180).map { index -> Double in
                let time = curve.outputDuration * Double(index) / 180
                return curve.velocity(at: time)
            }
            let minimum = samples.min() ?? 0
            let maximum = samples.max() ?? 0
            status.text = "Output: \(String(format: "%.3f", curve.outputDuration)) s · Velocity: \(String(format: "%.2f", minimum))× to \(String(format: "%.2f", maximum))×"
        } catch {
            status.text = "Invalid curve: \(error.localizedDescription)"
        }
    }

    private func editKeyframe(_ index: Int) {
        let existing = keyframes[index]
        let alert = UIAlertController(
            title: "Edit speed keyframe",
            message: "Velocity: 1 normal, 0 freeze, negative reverse. Tangent slopes can also be changed directly on the graph.",
            preferredStyle: .alert
        )
        let values = [
            String(format: "%.3f", existing.outputTime),
            String(format: "%.3f", existing.velocity),
            existing.incomingSlope.map { String(format: "%.3f", $0) } ?? "",
            existing.outgoingSlope.map { String(format: "%.3f", $0) } ?? "",
        ]
        let placeholders = ["Output time", "Velocity", "Incoming slope", "Outgoing slope"]
        for index in placeholders.indices {
            alert.addTextField { field in
                field.placeholder = placeholders[index]
                field.text = values[index]
                field.keyboardType = .numbersAndPunctuation
            }
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self, weak alert] _ in
            guard let self, let fields = alert?.textFields, fields.count == 4,
                  let time = Double(fields[0].text ?? ""),
                  let velocity = Double(fields[1].text ?? "") else { return }
            self.keyframes[index] = .init(
                id: existing.id,
                outputTime: max(0, time),
                velocity: velocity,
                incomingSlope: Double(fields[2].text ?? ""),
                outgoingSlope: Double(fields[3].text ?? "")
            )
            self.refresh()
        })
        present(alert, animated: true)
    }

    private func renderVideo(addToTimeline: Bool, sourceView: UIView?) {
        guard let sourceURL else {
            ExtensionUI.alert(title: "Choose a video", message: "Select a source video first.", from: self)
            return
        }
        let fps = max(1, min(120, Double(fpsField.text ?? "") ?? 30))
        let curve: SpeedCurve
        do { curve = try self.curve() } catch {
            ExtensionUI.alert(title: "Invalid curve", message: error.localizedDescription, from: self)
            return
        }
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AE-Motion-Speed-\(UUID().uuidString).mov")
        let options = VideoTimeRemapExportOptions(
            outputDuration: curve.outputDuration,
            frameRate: fps,
            includeAudio: includeAudioSwitch.isOn,
            preservePitch: preservePitchSwitch.isOn
        )
        progress.progress = 0
        status.text = addToTimeline ? "Rendering for timeline handoff…" : "Exporting retimed video…"

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.detached(priority: .userInitiated) {
                    try VideoTimeRemapExporter().export(
                        inputURL: sourceURL,
                        outputURL: outputURL,
                        curve: curve,
                        options: options
                    ) { value in
                        Task { @MainActor [weak self] in self?.progress.progress = Float(value) }
                    }
                }.value
                if addToTimeline {
                    self.status.text = "Rendered. Preparing Add Layer handoff…"
                    TimelineHandoffCoordinator.renderResultReady(fileURL: outputURL, from: self) { [weak self] result in
                        guard let self else { return }
                        switch result {
                        case .success:
                            self.status.text = "Saved as the newest Photos clip and opening Add Layer."
                        case .failure(let error):
                            self.status.text = "Rendered, but automatic handoff was incomplete."
                            ExtensionUI.alert(title: "Timeline handoff", message: error.localizedDescription, from: self)
                        }
                    }
                } else {
                    self.status.text = "Export complete."
                    ExtensionUI.share(fileURL: outputURL, from: self, source: sourceView)
                }
            } catch {
                self.status.text = "Export failed."
                ExtensionUI.alert(title: "Export failed", message: error.localizedDescription, from: self)
            }
        }
    }

    private func setPageScrollingEnabled(_ enabled: Bool) {
        pageScrollView?.panGestureRecognizer.isEnabled = enabled
        pageScrollView?.isDirectionalLockEnabled = !enabled
    }

    private func shareCurve(sourceView: UIView?) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(keyframes)
            ExtensionUI.share(text: String(decoding: data, as: UTF8.self), from: self, source: sourceView)
        } catch {
            ExtensionUI.alert(title: "Could not encode curve", message: error.localizedDescription, from: self)
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { keyframes.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let point = keyframes[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "keyframe", for: indexPath)
        var config = cell.defaultContentConfiguration()
        config.text = "\(String(format: "%.3f", point.outputTime)) s  ·  \(String(format: "%.3f", point.velocity))×"
        let inSlope = point.incomingSlope.map { String(format: "%.2f", $0) } ?? "auto"
        let outSlope = point.outgoingSlope.map { String(format: "%.2f", $0) } ?? "auto"
        config.secondaryText = "In: \(inSlope) · Out: \(outSlope)"
        cell.contentConfiguration = config
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        editKeyframe(indexPath.row)
    }

    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool { keyframes.count > 2 }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete, keyframes.count > 2 else { return }
        keyframes.remove(at: indexPath.row)
        refresh()
    }
}
#endif
