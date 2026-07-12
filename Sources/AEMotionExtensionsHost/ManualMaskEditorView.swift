#if canImport(UIKit)
import UIKit

struct NormalizedMaskPoint: Codable, Sendable, Equatable {
    var x: Double
    var y: Double
}

enum ManualMaskOperationKind: Int, Codable, Sendable {
    case keepStroke
    case removeStroke
    case keepRectangle
}

struct ManualMaskOperation: Codable, Sendable, Equatable {
    var kind: ManualMaskOperationKind
    var points: [NormalizedMaskPoint]
    var radius: Double
}

struct ManualMaskDefinition: Codable, Sendable, Equatable {
    var operations: [ManualMaskOperation] = []

    var isEmpty: Bool { operations.isEmpty }
}

@MainActor
final class ManualMaskEditorView: UIView {
    enum Mode: Int {
        case keepBrush
        case removeBrush
        case boxSelect
    }

    var mode: Mode = .keepBrush {
        didSet { canvas.mode = mode }
    }
    var brushRadius: Double = 0.045 {
        didSet { canvas.brushRadius = min(max(brushRadius, 0.005), 0.25) }
    }
    var onMaskChange: ((ManualMaskDefinition) -> Void)?
    var onInteractionChanged: ((Bool) -> Void)?

    private let imageView = UIImageView()
    private let canvas = ManualMaskCanvasView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .tertiarySystemBackground
        layer.cornerRadius = 14
        layer.masksToBounds = true

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .black
        addSubview(imageView)

        canvas.translatesAutoresizingMaskIntoConstraints = false
        addSubview(canvas)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            canvas.leadingAnchor.constraint(equalTo: leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: trailingAnchor),
            canvas.topAnchor.constraint(equalTo: topAnchor),
            canvas.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        canvas.mode = mode
        canvas.brushRadius = brushRadius
        canvas.onChange = { [weak self] definition in self?.onMaskChange?(definition) }
        canvas.onInteractionChanged = { [weak self] interacting in self?.onInteractionChanged?(interacting) }
        accessibilityLabel = "Manual cutout mask editor"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setImage(_ image: UIImage?) {
        imageView.image = image
        canvas.imageSize = image?.size ?? .zero
    }

    func definition() -> ManualMaskDefinition { canvas.definition }

    func undo() { canvas.undo() }

    func clear() { canvas.clear() }
}

@MainActor
private final class ManualMaskCanvasView: UIView, UIGestureRecognizerDelegate {
    var mode: ManualMaskEditorView.Mode = .keepBrush
    var brushRadius: Double = 0.045
    var imageSize: CGSize = .zero { didSet { setNeedsDisplay() } }
    var onChange: ((ManualMaskDefinition) -> Void)?
    var onInteractionChanged: ((Bool) -> Void)?
    private(set) var definition = ManualMaskDefinition()

    private var activeOperation: ManualMaskOperation?
    private var isInteracting = false
    private weak var linkedScrollView: UIScrollView?
    private lazy var drawGesture = UIPanGestureRecognizer(target: self, action: #selector(handleDrawGesture(_:)))

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isMultipleTouchEnabled = false
        isExclusiveTouch = true
        drawGesture.maximumNumberOfTouches = 1
        drawGesture.cancelsTouchesInView = true
        drawGesture.delegate = self
        addGestureRecognizer(drawGesture)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            setInteracting(false)
            linkedScrollView = nil
            return
        }
        var ancestor = superview
        while let view = ancestor {
            if let scroll = view as? UIScrollView {
                if linkedScrollView !== scroll {
                    scroll.panGestureRecognizer.require(toFail: drawGesture)
                    linkedScrollView = scroll
                }
                break
            }
            ancestor = view.superview
        }
    }

    func undo() {
        guard !definition.operations.isEmpty else { return }
        definition.operations.removeLast()
        setNeedsDisplay()
        onChange?(definition)
    }

    func clear() {
        definition.operations.removeAll()
        activeOperation = nil
        setNeedsDisplay()
        onChange?(definition)
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let imageRect = fittedImageRect()
        guard imageRect.width > 1, imageRect.height > 1 else { return }
        context.saveGState()
        context.clip(to: imageRect)
        for operation in definition.operations {
            draw(operation, in: imageRect, context: context)
        }
        if let activeOperation {
            draw(activeOperation, in: imageRect, context: context)
        }
        context.restoreGState()
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === drawGesture else { return true }
        return normalizedPoint(from: gestureRecognizer.location(in: self)) != nil
    }

    @objc private func handleDrawGesture(_ gesture: UIPanGestureRecognizer) {
        let location = gesture.location(in: self)
        switch gesture.state {
        case .began:
            guard let point = normalizedPoint(from: location) else { return }
            setInteracting(true)
            let kind: ManualMaskOperationKind
            switch mode {
            case .keepBrush: kind = .keepStroke
            case .removeBrush: kind = .removeStroke
            case .boxSelect: kind = .keepRectangle
            }
            activeOperation = ManualMaskOperation(kind: kind, points: [point], radius: brushRadius)
            setNeedsDisplay()
        case .changed:
            guard var operation = activeOperation,
                  let point = normalizedPoint(from: location, clampToImage: true) else { return }
            switch operation.kind {
            case .keepRectangle:
                if operation.points.count == 1 { operation.points.append(point) }
                else { operation.points[1] = point }
            case .keepStroke, .removeStroke:
                if let previous = operation.points.last {
                    let dx = previous.x - point.x
                    let dy = previous.y - point.y
                    if sqrt(dx * dx + dy * dy) < 0.002 { return }
                }
                operation.points.append(point)
            }
            activeOperation = operation
            setNeedsDisplay()
        case .ended:
            commitActiveOperation()
            setInteracting(false)
        case .cancelled, .failed:
            activeOperation = nil
            setNeedsDisplay()
            setInteracting(false)
        default:
            break
        }
    }

    private func commitActiveOperation() {
        guard var operation = activeOperation else { return }
        activeOperation = nil
        if operation.kind == .keepRectangle, operation.points.count == 1 {
            let point = operation.points[0]
            let delta = max(0.01, operation.radius)
            operation.points.append(.init(
                x: min(1, point.x + delta),
                y: min(1, point.y + delta)
            ))
        }
        guard !operation.points.isEmpty else { return }
        definition.operations.append(operation)
        setNeedsDisplay()
        onChange?(definition)
    }

    private func setInteracting(_ interacting: Bool) {
        guard isInteracting != interacting else { return }
        isInteracting = interacting
        onInteractionChanged?(interacting)
    }

    private func fittedImageRect() -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
              bounds.width > 0, bounds.height > 0 else { return .zero }
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: bounds.midX - size.width * 0.5,
            y: bounds.midY - size.height * 0.5,
            width: size.width,
            height: size.height
        )
    }

    private func normalizedPoint(
        from location: CGPoint,
        clampToImage: Bool = false
    ) -> NormalizedMaskPoint? {
        let imageRect = fittedImageRect()
        guard imageRect.width > 0, imageRect.height > 0 else { return nil }
        if !clampToImage && !imageRect.contains(location) { return nil }
        let x = min(max((location.x - imageRect.minX) / imageRect.width, 0), 1)
        let y = min(max((location.y - imageRect.minY) / imageRect.height, 0), 1)
        return .init(x: Double(x), y: Double(y))
    }

    private func draw(
        _ operation: ManualMaskOperation,
        in imageRect: CGRect,
        context: CGContext
    ) {
        let color: UIColor
        switch operation.kind {
        case .keepStroke: color = UIColor.systemGreen.withAlphaComponent(0.58)
        case .removeStroke: color = UIColor.systemRed.withAlphaComponent(0.62)
        case .keepRectangle: color = UIColor.systemYellow.withAlphaComponent(0.38)
        }
        context.saveGState()
        context.setStrokeColor(color.cgColor)
        context.setFillColor(color.cgColor)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        switch operation.kind {
        case .keepStroke, .removeStroke:
            let width = CGFloat(max(0.005, operation.radius)) * min(imageRect.width, imageRect.height) * 2
            context.setLineWidth(width)
            guard let first = operation.points.first else { break }
            context.beginPath()
            context.move(to: screenPoint(first, in: imageRect))
            if operation.points.count == 1 {
                let point = screenPoint(first, in: imageRect)
                context.addLine(to: CGPoint(x: point.x + 0.01, y: point.y + 0.01))
            } else {
                for point in operation.points.dropFirst() {
                    context.addLine(to: screenPoint(point, in: imageRect))
                }
            }
            context.strokePath()
        case .keepRectangle:
            guard operation.points.count >= 2 else { break }
            let a = screenPoint(operation.points[0], in: imageRect)
            let b = screenPoint(operation.points[1], in: imageRect)
            let rectangle = CGRect(
                x: min(a.x, b.x),
                y: min(a.y, b.y),
                width: abs(a.x - b.x),
                height: abs(a.y - b.y)
            )
            context.fill(rectangle)
            context.setStrokeColor(UIColor.systemYellow.cgColor)
            context.setLineWidth(2)
            context.stroke(rectangle)
        }
        context.restoreGState()
    }

    private func screenPoint(_ point: NormalizedMaskPoint, in imageRect: CGRect) -> CGPoint {
        CGPoint(
            x: imageRect.minX + CGFloat(point.x) * imageRect.width,
            y: imageRect.minY + CGFloat(point.y) * imageRect.height
        )
    }
}
#endif
