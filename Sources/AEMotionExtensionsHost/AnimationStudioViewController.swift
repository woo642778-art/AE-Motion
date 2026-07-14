#if canImport(UIKit)
import UIKit
import AEMotionExtensionsCore

@MainActor
final class AnimationStudioViewController: UIViewController, UIGestureRecognizerDelegate {
    private let mode = UISegmentedControl(items: ["Graph", "Gesture", "Velocity"])
    private let graph = AnimationPreviewView()
    private let status = UILabel()
    private let slider = UISlider()
    private let primary = UIButton(type: .system)
    private let secondary = UIButton(type: .system)
    private var recorder = GestureRecorder()
    private var recordingStart: CFTimeInterval?
    private var isRecording = false
    private var position = CGPoint(x: 120, y: 100)
    private var rotation = 0.0
    private var scale = 1.0
    private var velocity = ProfessionalVelocityPlan.ramp(duration: 2, from: 0.5, to: 2)

    override func viewDidLoad() {
        super.viewDidLoad(); title = "Animation Core"; AEMotionTheme.apply(to: self)
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(close))
        mode.selectedSegmentIndex = 0; mode.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        graph.translatesAutoresizingMaskIntoConstraints = false; graph.backgroundColor = AEMotionTheme.surface; graph.layer.cornerRadius = 14; graph.layer.cornerCurve = .continuous
        status.numberOfLines = 0; status.font = .preferredFont(forTextStyle: .footnote); status.textColor = AEMotionTheme.secondaryText
        slider.minimumValue = 0; slider.maximumValue = 2; slider.addTarget(self, action: #selector(scrub), for: .valueChanged)
        primary.configuration = .filled(); primary.addTarget(self, action: #selector(primaryAction), for: .touchUpInside)
        secondary.configuration = .bordered(); secondary.addTarget(self, action: #selector(secondaryAction), for: .touchUpInside)
        let actions = UIStackView(arrangedSubviews: [primary, secondary]); actions.axis = .horizontal; actions.distribution = .fillEqually; actions.spacing = 10
        let stack = UIStackView(arrangedSubviews: [mode, graph, slider, status, actions]); stack.axis = .vertical; stack.spacing = 14; stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16), stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16), stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 14), graph.heightAnchor.constraint(equalToConstant: 300)])
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan)), pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch)), rotate = UIRotationGestureRecognizer(target: self, action: #selector(handleRotation))
        [pan, pinch, rotate].forEach { $0.delegate = self; graph.addGestureRecognizer($0) }; graph.isUserInteractionEnabled = true; modeChanged()
    }

    nonisolated func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
    @objc private func close() { dismiss(animated: true) }

    @objc private func modeChanged() {
        slider.value = 0
        switch mode.selectedSegmentIndex {
        case 0:
            graph.mode = .value
            graph.curve = AnimationKeyframeCurve(keyframes: [Keyframe(time: 0, value: .scalar(0), interpolation: .back), Keyframe(time: 0.65, value: .scalar(1.18), interpolation: .autoBezier), Keyframe(time: 1.2, value: .scalar(1), interpolation: .linear)])
            slider.maximumValue = 1.2; primary.setTitle("Value Graph", for: .normal); secondary.setTitle("Speed Graph", for: .normal)
            status.text = "One curve model now drives scalar, point, color and angle properties with hold, linear, Bezier, back, bounce and elastic interpolation."
        case 1:
            graph.mode = .gesture; slider.maximumValue = 2; primary.setTitle("Start Recording", for: .normal); secondary.setTitle("Clear", for: .normal)
            status.text = "Drag, pinch and rotate together. Motion Cleanup smooths and simplifies the captured 60 fps path."; drawGestureObject()
        default:
            graph.mode = .velocity; graph.velocityCurve = velocity.curve; slider.maximumValue = 2; primary.setTitle("Freeze", for: .normal); secondary.setTitle("Reverse", for: .normal)
            status.text = "Professional Velocity supports ramps, freeze frames, reverse segments, BPM markers, frame blending and optical-flow handoff metadata."
        }
        graph.setNeedsDisplay()
    }

    @objc private func scrub() {
        graph.playhead = Double(slider.value); graph.setNeedsDisplay()
        if mode.selectedSegmentIndex == 2 { status.text = String(format: "%.2fs  •  %.2fx  •  source %.2fs", slider.value, velocity.curve.speed(at: Double(slider.value)), velocity.curve.sourceTime(at: Double(slider.value))) }
    }

    @objc private func primaryAction() {
        switch mode.selectedSegmentIndex {
        case 0: graph.mode = .value
        case 1:
            isRecording.toggle()
            if isRecording { recorder.reset(); recordingStart = CACurrentMediaTime(); primary.setTitle("Stop Recording", for: .normal) }
            else { let raw = recorder.sampleCount, result = recorder.finish(cleanup: true); primary.setTitle("Start Recording", for: .normal); status.text = "Recorded \(raw) samples. Motion Cleanup produced \(result.position.curve.keyframes.count) position, \(result.rotation.curve.keyframes.count) rotation and \(result.scale.curve.keyframes.count) scale keyframes." }
        default:
            velocity = .freeze(duration: 2, sourceTime: velocity.curve.sourceTime(at: Double(slider.value))); graph.velocityCurve = velocity.curve; graph.setNeedsDisplay(); scrub()
        }
    }

    @objc private func secondaryAction() {
        switch mode.selectedSegmentIndex {
        case 0: graph.mode = .speed; graph.setNeedsDisplay()
        case 1: recorder.reset(); position = CGPoint(x: 120, y: 100); rotation = 0; scale = 1; drawGestureObject(); status.text = "Gesture recording cleared."
        default: velocity = .reverse(duration: 2, sourceEnd: 2); graph.velocityCurve = velocity.curve; graph.setNeedsDisplay(); scrub()
        }
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        guard mode.selectedSegmentIndex == 1 else { return }; let delta = recognizer.translation(in: graph); recognizer.setTranslation(.zero, in: graph)
        position.x = min(max(position.x + delta.x, 24), max(24, graph.bounds.width - 24)); position.y = min(max(position.y + delta.y, 24), max(24, graph.bounds.height - 24)); record(); drawGestureObject()
    }
    @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) { guard mode.selectedSegmentIndex == 1 else { return }; scale = min(max(scale * recognizer.scale, 0.2), 4); recognizer.scale = 1; record(); drawGestureObject() }
    @objc private func handleRotation(_ recognizer: UIRotationGestureRecognizer) { guard mode.selectedSegmentIndex == 1 else { return }; rotation += recognizer.rotation * 180 / .pi; recognizer.rotation = 0; record(); drawGestureObject() }
    private func record() { guard isRecording, let start = recordingStart else { return }; recorder.append(.init(time: CACurrentMediaTime() - start, x: position.x, y: position.y, rotation: rotation, scale: scale)) }
    private func drawGestureObject() { graph.gestureTransform = (position, rotation, scale); graph.setNeedsDisplay() }
}

@MainActor
private final class AnimationPreviewView: UIView {
    enum Mode { case value, speed, gesture, velocity }
    var mode: Mode = .value
    var curve = AnimationKeyframeCurve()
    var velocityCurve = VelocityCurve.constant(duration: 2, speed: 1)
    var playhead = 0.0
    var gestureTransform: (CGPoint, Double, Double) = (CGPoint(x: 120, y: 100), 0, 1)
    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.setStrokeColor(AEMotionTheme.separator.cgColor); context.setLineWidth(1)
        for index in 1..<5 { let x = rect.width * CGFloat(index) / 5; context.move(to: CGPoint(x: x, y: 0)); context.addLine(to: CGPoint(x: x, y: rect.height)); let y = rect.height * CGFloat(index) / 5; context.move(to: CGPoint(x: 0, y: y)); context.addLine(to: CGPoint(x: rect.width, y: y)) }
        context.strokePath()
        if mode == .gesture { let (point, degrees, factor) = gestureTransform; context.saveGState(); context.translateBy(x: point.x, y: point.y); context.rotate(by: degrees * .pi / 180); context.scaleBy(x: factor, y: factor); AEMotionTheme.accent.setFill(); UIBezierPath(roundedRect: CGRect(x: -24, y: -24, width: 48, height: 48), cornerRadius: 12).fill(); context.restoreGState(); return }
        let duration = max(mode == .velocity ? velocityCurve.keyframes.last?.time ?? 2 : curve.keyframes.last?.time ?? 1, 0.001), path = UIBezierPath()
        for index in 0...160 {
            let t = duration * Double(index) / 160, raw: Double
            if mode == .velocity { raw = velocityCurve.speed(at: t) } else if mode == .speed { raw = curve.speed(at: t, fallback: .scalar(0)) } else if case let .scalar(value) = curve.value(at: t, fallback: .scalar(0)) { raw = value } else { raw = 0 }
            let normalized = mode == .speed ? min(raw / 5, 1) : mode == .velocity ? min(max((raw + 2) / 4, 0), 1) : min(max(raw / 1.3, 0), 1)
            let point = CGPoint(x: rect.width * CGFloat(t / duration), y: rect.height * CGFloat(1 - normalized)); index == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        AEMotionTheme.accent.setStroke(); path.lineWidth = 2.5; path.stroke(); let playheadX = rect.width * CGFloat(min(max(playhead / duration, 0), 1)); context.setStrokeColor(UIColor.systemRed.cgColor); context.move(to: CGPoint(x: playheadX, y: 0)); context.addLine(to: CGPoint(x: playheadX, y: rect.height)); context.strokePath()
    }
}
#endif
