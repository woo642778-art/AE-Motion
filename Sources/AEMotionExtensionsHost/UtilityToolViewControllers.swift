#if canImport(UIKit)
import UIKit
import AEMotionExtensionsCore

final class BPMCalculatorViewController: UIViewController {
    private let bpm = ExtensionUI.field("BPM", value: "120")
    private let fps = ExtensionUI.field("FPS", value: "30")
    private let beats = ExtensionUI.field("Beat number", value: "4")
    private let result = ExtensionUI.label("Enter values and calculate.")

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "BPM / Beat / Frame"
        view.backgroundColor = .systemBackground
        let button = ExtensionUI.button("Calculate", action: UIAction { [weak self] _ in self?.calculate() })
        ExtensionUI.installScrollStack(ExtensionUI.stack([
            ExtensionUI.label("Convert musical timing into exact project frames."), bpm, fps, beats, button, result
        ]), in: self)
        calculate()
    }

    private func calculate() {
        let bpmValue = Double(bpm.text ?? "") ?? 0
        let fpsValue = Double(fps.text ?? "") ?? 0
        let beatValue = Double(beats.text ?? "") ?? 0
        guard bpmValue > 0, fpsValue > 0 else {
            result.text = "BPM and FPS must be greater than zero."
            return
        }
        let fpb = BPMFrameCalculator.framesPerBeat(bpm: bpmValue, fps: fpsValue)
        let frame = BPMFrameCalculator.frame(forBeat: beatValue, bpm: bpmValue, fps: fpsValue)
        result.text = String(format: "Seconds per beat: %.4f\nFrames per beat: %.3f\nBeat %.2f → frame %d", 60 / bpmValue, fpb, beatValue, frame)
    }
}

final class EasingCurveViewController: UIViewController {
    private let duration = ExtensionUI.field("Duration frames", value: "30")
    private let samples = ExtensionUI.field("Samples", value: "32")
    private let editor = InteractiveCurveEditorView()
    private let output = UITextView()
    private weak var pageScrollView: UIScrollView?
    private var csv = ""
    private var isSyncing = false

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Easing Curve Generator"
        view.backgroundColor = .systemBackground

        editor.heightAnchor.constraint(equalToConstant: 300).isActive = true
        editor.xDomain = 0...1
        editor.yDomain = -0.35...1.35
        editor.lockFirstX = true
        editor.lockLastX = true
        editor.lockFirstY = true
        editor.lockLastY = true
        editor.minimumPointCount = 2
        editor.onChange = { [weak self] _ in self?.generate() }
        editor.onInteractionChanged = { [weak self] interacting in
            self?.setPageScrollingEnabled(!interacting)
        }

        output.isEditable = false
        output.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        output.heightAnchor.constraint(equalToConstant: 180).isActive = true

        let reset = ExtensionUI.secondaryButton("Reset", action: UIAction { [weak self] _ in self?.applyPreset("Ease In-Out") })
        let delete = ExtensionUI.secondaryButton("Delete Selected", action: UIAction { [weak self] _ in self?.editor.deleteSelectedPoint() })
        let controls = ExtensionUI.horizontalStack([reset, delete])
        let share = ExtensionUI.button("Share CSV", action: UIAction { [weak self] action in
            guard let self else { return }
            ExtensionUI.share(text: self.csv, from: self, source: action.sender as? UIView)
        })

        pageScrollView = ExtensionUI.installScrollStack(ExtensionUI.stack([
            ExtensionUI.label("Flow-style easing editor. Drag points and orange tangent handles. Page scrolling locks automatically while the graph is being edited. Double-tap the graph to add a point."),
            makePresetScroller(),
            editor,
            controls,
            duration,
            samples,
            share,
            output,
        ]), in: self)
        applyPreset("Ease In-Out")
    }

    private func setPageScrollingEnabled(_ enabled: Bool) {
        pageScrollView?.panGestureRecognizer.isEnabled = enabled
        pageScrollView?.isDirectionalLockEnabled = !enabled
    }

    private func makePresetScroller() -> UIView {
        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        for name in ["Linear", "Ease In", "Ease Out", "Ease In-Out", "Back", "Elastic"] {
            let button = ExtensionUI.secondaryButton(name, action: UIAction { [weak self] _ in self?.applyPreset(name) })
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 92).isActive = true
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

    private func applyPreset(_ name: String) {
        let points: [EditableCurvePoint]
        switch name {
        case "Linear":
            points = [
                .init(x: 0, y: 0, incomingSlope: 1, outgoingSlope: 1),
                .init(x: 1, y: 1, incomingSlope: 1, outgoingSlope: 1),
            ]
        case "Ease In":
            points = [
                .init(x: 0, y: 0, incomingSlope: 0, outgoingSlope: 0),
                .init(x: 1, y: 1, incomingSlope: 2.2, outgoingSlope: 2.2),
            ]
        case "Ease Out":
            points = [
                .init(x: 0, y: 0, incomingSlope: 2.2, outgoingSlope: 2.2),
                .init(x: 1, y: 1, incomingSlope: 0, outgoingSlope: 0),
            ]
        case "Back":
            points = [
                .init(x: 0, y: 0, incomingSlope: -0.8, outgoingSlope: -0.8),
                .init(x: 0.72, y: 1.16, incomingSlope: 0.4, outgoingSlope: 0.4),
                .init(x: 1, y: 1, incomingSlope: 0, outgoingSlope: 0),
            ]
        case "Elastic":
            points = [
                .init(x: 0, y: 0, incomingSlope: 0, outgoingSlope: 0),
                .init(x: 0.58, y: 1.18, incomingSlope: 0, outgoingSlope: -3),
                .init(x: 0.78, y: 0.92, incomingSlope: 0, outgoingSlope: 1.4),
                .init(x: 1, y: 1, incomingSlope: 0, outgoingSlope: 0),
            ]
        default:
            points = [
                .init(x: 0, y: 0, incomingSlope: 0, outgoingSlope: 0),
                .init(x: 1, y: 1, incomingSlope: 0, outgoingSlope: 0),
            ]
        }
        isSyncing = true
        editor.setPoints(points)
        isSyncing = false
        generate()
    }

    private func generate() {
        guard !isSyncing else { return }
        let count = max(2, min(500, Int(samples.text ?? "") ?? 32))
        let frames = max(1, Int(duration.text ?? "") ?? 30)
        let sampled = editor.sampledPoints(count: count)
        let points = sampled.enumerated().map { index, sample in
            KeyframePoint(frame: Int((sample.x * Double(frames)).rounded()), value: sample.y)
        }
        csv = "frame,value\n" + points.map {
            "\($0.frame),\(String(format: "%.6f", $0.value))"
        }.joined(separator: "\n")
        output.text = csv
    }
}
final class RandomValuesViewController: UIViewController {
    private let count = ExtensionUI.field("Count", value: "12")
    private let minimum = ExtensionUI.field("Minimum", value: "-10")
    private let maximum = ExtensionUI.field("Maximum", value: "10")
    private let seed = ExtensionUI.field("Seed", value: "42")
    private let output = UITextView()
    private var text = ""

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Random Value Generator"
        view.backgroundColor = .systemBackground
        output.isEditable = false
        output.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        output.heightAnchor.constraint(equalToConstant: 240).isActive = true
        let generateButton = ExtensionUI.button("Generate", action: UIAction { [weak self] _ in self?.generate() })
        let share = ExtensionUI.button("Share Values", action: UIAction { [weak self] action in
            guard let self else { return }
            ExtensionUI.share(text: self.text, from: self, source: nil)
        })
        ExtensionUI.installScrollStack(ExtensionUI.stack([
            ExtensionUI.label("Seeded values are repeatable, useful for shake and procedural animation."), count, minimum, maximum, seed, generateButton, share, output
        ]), in: self)
        generate()
    }

    private func generate() {
        let n = max(1, min(500, Int(count.text ?? "") ?? 12))
        let minValue = Double(minimum.text ?? "") ?? -10
        let maxValue = Double(maximum.text ?? "") ?? 10
        let seedValue = UInt64(seed.text ?? "") ?? 42
        guard minValue <= maxValue else { output.text = "Minimum must not exceed maximum."; return }
        let values = RandomValueGenerator.values(count: n, range: minValue...maxValue, seed: seedValue)
        text = values.enumerated().map { "\($0.offset),\(String(format: "%.6f", $0.element))" }.joined(separator: "\n")
        output.text = text
    }
}

final class LayerOffsetViewController: UIViewController {
    private let count = ExtensionUI.field("Layer count", value: "8")
    private let first = ExtensionUI.field("First frame", value: "0")
    private let offset = ExtensionUI.field("Offset frames", value: "3")
    private let result = ExtensionUI.label("")

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Layer Offset Planner"
        view.backgroundColor = .systemBackground
        let calculateButton = ExtensionUI.button("Calculate", action: UIAction { [weak self] _ in self?.calculate() })
        ExtensionUI.installScrollStack(ExtensionUI.stack([
            ExtensionUI.label("Plan sequential layer starts for cascades and typography."), count, first, offset, calculateButton, result
        ]), in: self)
        calculate()
    }

    private func calculate() {
        let values = LayerOffsetPlanner.startFrames(
            layerCount: max(1, Int(count.text ?? "") ?? 8),
            firstFrame: Int(first.text ?? "") ?? 0,
            offsetFrames: Int(offset.text ?? "") ?? 3
        )
        result.text = values.enumerated().map { "Layer \($0.offset + 1): frame \($0.element)" }.joined(separator: "\n")
    }
}

final class CameraShakeViewController: UIViewController {
    private let count = ExtensionUI.field("Samples", value: "24")
    private let amplitude = ExtensionUI.field("Amplitude", value: "20")
    private let decay = ExtensionUI.field("Decay 0–1", value: "0.93")
    private let seed = ExtensionUI.field("Seed", value: "7")
    private let output = UITextView()
    private var csv = ""

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Camera Shake Generator"
        view.backgroundColor = .systemBackground
        output.isEditable = false
        output.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        output.heightAnchor.constraint(equalToConstant: 260).isActive = true
        let generateButton = ExtensionUI.button("Generate", action: UIAction { [weak self] _ in self?.generate() })
        let share = ExtensionUI.button("Share CSV", action: UIAction { [weak self] action in
            guard let self else { return }
            ExtensionUI.share(text: self.csv, from: self, source: nil)
        })
        ExtensionUI.installScrollStack(ExtensionUI.stack([
            ExtensionUI.label("Generate deterministic X, Y and rotation samples."), count, amplitude, decay, seed, generateButton, share, output
        ]), in: self)
        generate()
    }

    private func generate() {
        let values = CameraShakeGenerator.samples(
            count: max(1, min(500, Int(count.text ?? "") ?? 24)),
            amplitude: max(0, Double(amplitude.text ?? "") ?? 20),
            decay: max(0, min(1, Double(decay.text ?? "") ?? 0.93)),
            seed: UInt64(seed.text ?? "") ?? 7
        )
        csv = "sample,x,y,rotation\n" + values.enumerated().map {
            "\($0.offset),\(String(format: "%.4f", $0.element.x)),\(String(format: "%.4f", $0.element.y)),\(String(format: "%.4f", $0.element.rotation))"
        }.joined(separator: "\n")
        output.text = csv
    }
}

final class ExpressionHelperViewController: UITableViewController {
    private let items = ExpressionHelper.snippets.sorted { $0.key < $1.key }
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Expression Helper"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "expression")
    }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { items.count }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let item = items[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "expression", for: indexPath)
        var config = cell.defaultContentConfiguration()
        config.text = item.key
        config.secondaryText = item.value
        config.secondaryTextProperties.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        cell.contentConfiguration = config
        cell.accessoryType = .detailButton
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let value = items[indexPath.row].value
        UIPasteboard.general.string = value
        tableView.deselectRow(at: indexPath, animated: true)
        ExtensionUI.alert(title: "Copied", message: value, from: self)
    }
}

final class PresetBrowserViewController: UITableViewController {
    private let presets: [(String, String)] = [
        ("Smooth Push", "Position: 0 → 100, cubic ease-in-out, 18–24 frames"),
        ("Impact Zoom", "Scale: 100 → 118 → 100 with fast overshoot"),
        ("Elastic Overshoot", "Use Back easing and 8–14% overshoot"),
        ("Handheld Drift", "Low-amplitude seeded shake with slow decay"),
        ("Tracking Reveal", "Tracking wide → normal while opacity rises"),
        ("Word Cascade", "Offset each word or layer by 2–4 frames"),
    ]
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Motion Presets"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "preset")
    }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { presets.count }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let preset = presets[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "preset", for: indexPath)
        var config = cell.defaultContentConfiguration()
        config.text = preset.0
        config.secondaryText = preset.1
        cell.contentConfiguration = config
        return cell
    }
}

final class ColorPaletteViewController: UIViewController {
    private let hue = ExtensionUI.field("Hue 0–360", value: "210")
    private let saturation = ExtensionUI.field("Saturation 0–1", value: "0.75")
    private let lightness = ExtensionUI.field("Lightness 0–1", value: "0.55")
    private let paletteStack = UIStackView()
    private var hexText = ""

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Color Palette Generator"
        view.backgroundColor = .systemBackground
        paletteStack.axis = .vertical
        paletteStack.spacing = 8
        let generateButton = ExtensionUI.button("Generate", action: UIAction { [weak self] _ in self?.generate() })
        let share = ExtensionUI.button("Share HEX", action: UIAction { [weak self] action in
            guard let self else { return }
            ExtensionUI.share(text: self.hexText, from: self, source: nil)
        })
        ExtensionUI.installScrollStack(ExtensionUI.stack([
            ExtensionUI.label("Build a five-color analogous palette."), hue, saturation, lightness, generateButton, share, paletteStack
        ]), in: self)
        generate()
    }

    private func generate() {
        paletteStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let colors = ColorPaletteGenerator.analogous(
            hue: Double(hue.text ?? "") ?? 210,
            saturation: max(0, min(1, Double(saturation.text ?? "") ?? 0.75)),
            lightness: max(0, min(1, Double(lightness.text ?? "") ?? 0.55))
        )
        let hexes = colors.map { color -> String in
            let r = Int((color.red * 255).rounded())
            let g = Int((color.green * 255).rounded())
            let b = Int((color.blue * 255).rounded())
            return String(format: "#%02X%02X%02X", r, g, b)
        }
        hexText = hexes.joined(separator: "\n")
        for (index, color) in colors.enumerated() {
            let row = UILabel()
            row.text = "   \(hexes[index])"
            row.font = .monospacedSystemFont(ofSize: 15, weight: .semibold)
            let luminance = 0.2126 * color.red + 0.7152 * color.green + 0.0722 * color.blue
            row.textColor = luminance > 0.62 ? .black : .white
            row.backgroundColor = UIColor(red: CGFloat(color.red), green: CGFloat(color.green), blue: CGFloat(color.blue), alpha: 1)
            row.layer.cornerRadius = 8
            row.layer.masksToBounds = true
            row.heightAnchor.constraint(equalToConstant: 52).isActive = true
            paletteStack.addArrangedSubview(row)
        }
    }
}
#endif
