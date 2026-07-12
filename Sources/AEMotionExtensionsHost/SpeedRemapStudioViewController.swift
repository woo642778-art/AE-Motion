#if canImport(UIKit) && canImport(AVFoundation) && canImport(UniformTypeIdentifiers)
import UIKit
import AVFoundation
import UniformTypeIdentifiers
import AEMotionExtensionsCore

final class SpeedRemapStudioViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UIDocumentPickerDelegate {
    private let sourceLabel = ExtensionUI.label("No source video selected.")
    private let fpsField = ExtensionUI.field("Output FPS", value: "30")
    private let graph = CurveGraphView()
    private let table = UITableView(frame: .zero, style: .insetGrouped)
    private let progress = UIProgressView(progressViewStyle: .default)
    private let status = ExtensionUI.label("1× normal · 0 freeze · negative reverse")
    private var sourceURL: URL?
    private var sourceDuration: Double = 3
    private var keyframes: [SpeedKeyframe] = [
        .init(outputTime: 0, velocity: 1, incomingSlope: 0, outgoingSlope: 0),
        .init(outputTime: 3, velocity: 1, incomingSlope: 0, outgoingSlope: 0),
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Speed Remap Studio"
        view.backgroundColor = .systemBackground

        graph.heightAnchor.constraint(equalToConstant: 220).isActive = true
        graph.horizontalZero = 0
        table.dataSource = self
        table.delegate = self
        table.register(UITableViewCell.self, forCellReuseIdentifier: "keyframe")
        table.heightAnchor.constraint(equalToConstant: 260).isActive = true
        progress.progress = 0

        let choose = ExtensionUI.button("Choose Video", action: UIAction { [weak self] _ in self?.chooseVideo() })
        let add = ExtensionUI.button("Add Speed Keyframe", action: UIAction { [weak self] _ in self?.editKeyframe(nil) })
        let presets = UISegmentedControl(items: ["Normal", "Ramp", "Impact", "Freeze", "Reverse"])
        presets.selectedSegmentIndex = 0
        presets.addAction(UIAction { [weak self] action in
            guard let control = action.sender as? UISegmentedControl else { return }
            self?.applyPreset(control.selectedSegmentIndex)
        }, for: .valueChanged)
        let export = ExtensionUI.button("Export Retimed Video", action: UIAction { [weak self] action in
            self?.exportVideo(sourceView: nil)
        })
        let shareCurve = ExtensionUI.button("Share Speed Curve JSON", action: UIAction { [weak self] action in
            self?.shareCurve(sourceView: nil)
        })

        ExtensionUI.installScrollStack(ExtensionUI.stack([
            ExtensionUI.label("Velocity graph with keyframed speed, reverse and freeze. The current build exports a new video for re-import; it does not yet write directly into Alight Motion's private project model."),
            choose, sourceLabel, presets, graph, fpsField, add, table, status, progress, export, shareCurve
        ]), in: self)
        refresh()
    }

    private func chooseVideo() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.movie], asCopy: true)
        picker.delegate = self
        present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        sourceURL = url
        let asset = AVURLAsset(url: url)
        sourceDuration = max(0.1, asset.duration.seconds)
        keyframes = [
            .init(outputTime: 0, velocity: 1, incomingSlope: 0, outgoingSlope: 0),
            .init(outputTime: sourceDuration, velocity: 1, incomingSlope: 0, outgoingSlope: 0),
        ]
        sourceLabel.text = "\(url.lastPathComponent)\nSource duration: \(String(format: "%.3f", sourceDuration)) s"
        refresh()
    }

    private func applyPreset(_ index: Int) {
        let duration = max(0.5, sourceDuration)
        switch index {
        case 1: keyframes = SpeedRemapPreset.smoothRamp(duration: duration)
        case 2: keyframes = SpeedRemapPreset.impact(duration: duration)
        case 3: keyframes = SpeedRemapPreset.freezeHit(duration: duration)
        case 4:
            keyframes = [
                .init(outputTime: 0, velocity: -1, incomingSlope: 0, outgoingSlope: 0),
                .init(outputTime: duration, velocity: -1, incomingSlope: 0, outgoingSlope: 0),
            ]
        default:
            keyframes = [
                .init(outputTime: 0, velocity: 1, incomingSlope: 0, outgoingSlope: 0),
                .init(outputTime: duration, velocity: 1, incomingSlope: 0, outgoingSlope: 0),
            ]
        }
        refresh()
    }

    private func curve() throws -> SpeedCurve {
        let reverseOnly = keyframes.allSatisfy { $0.velocity < 0 }
        return try SpeedCurve(sourceOrigin: reverseOnly ? sourceDuration : 0, keyframes: keyframes)
    }

    private func refresh() {
        keyframes.sort { $0.outputTime < $1.outputTime }
        table.reloadData()
        do {
            let curve = try curve()
            let duration = max(0.001, curve.outputDuration)
            graph.points = (0...160).map { index in
                let time = duration * Double(index) / 160
                return (time, curve.velocity(at: time))
            }
            let minVelocity = graph.points.map(\.y).min() ?? 0
            let maxVelocity = graph.points.map(\.y).max() ?? 0
            status.text = "Output: \(String(format: "%.3f", duration)) s · Velocity range: \(String(format: "%.2f", minVelocity))× to \(String(format: "%.2f", maxVelocity))×"
        } catch {
            graph.points = []
            status.text = "Invalid curve: \(error.localizedDescription)"
        }
    }

    private func editKeyframe(_ existingIndex: Int?) {
        let existing = existingIndex.map { keyframes[$0] }
        let alert = UIAlertController(title: existing == nil ? "Add keyframe" : "Edit keyframe", message: "Velocity: 1 normal, 0 freeze, negative reverse. Slopes control the graph handles.", preferredStyle: .alert)
        let values = [
            existing.map { String(format: "%.3f", $0.outputTime) } ?? String(format: "%.3f", max(0, sourceDuration * 0.5)),
            existing.map { String(format: "%.3f", $0.velocity) } ?? "1",
            existing?.incomingSlope.map { String(format: "%.3f", $0) } ?? "",
            existing?.outgoingSlope.map { String(format: "%.3f", $0) } ?? "",
        ]
        let placeholders = ["Output time (seconds)", "Velocity", "Incoming slope (optional)", "Outgoing slope (optional)"]
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
            let incoming = Double(fields[2].text ?? "")
            let outgoing = Double(fields[3].text ?? "")
            let point = SpeedKeyframe(
                id: existing?.id ?? UUID(),
                outputTime: max(0, time),
                velocity: velocity,
                incomingSlope: incoming,
                outgoingSlope: outgoing
            )
            if let existingIndex { self.keyframes[existingIndex] = point } else { self.keyframes.append(point) }
            self.refresh()
        })
        present(alert, animated: true)
    }

    private func exportVideo(sourceView: UIView?) {
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
        let exporter = VideoTimeRemapExporter()
        progress.progress = 0
        status.text = "Exporting video only…"

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.detached(priority: .userInitiated) {
                    try exporter.export(
                        inputURL: sourceURL,
                        outputURL: outputURL,
                        curve: curve,
                        options: VideoTimeRemapExportOptions(outputDuration: curve.outputDuration, frameRate: fps)
                    ) { value in
                        Task { @MainActor [weak self] in self?.progress.progress = Float(value) }
                    }
                }.value
                self.status.text = "Export complete. Audio is not included in this build."
                ExtensionUI.share(fileURL: outputURL, from: self, source: sourceView)
            } catch {
                self.status.text = "Export failed."
                ExtensionUI.alert(title: "Export failed", message: error.localizedDescription, from: self)
            }
        }
    }

    private func shareCurve(sourceView: UIView?) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(keyframes)
            let text = String(decoding: data, as: UTF8.self)
            ExtensionUI.share(text: text, from: self, source: sourceView)
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
        config.secondaryText = "In slope: \(inSlope) · Out slope: \(outSlope)"
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
