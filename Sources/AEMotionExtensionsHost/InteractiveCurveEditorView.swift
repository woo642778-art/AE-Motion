#if canImport(UIKit)
import UIKit

struct EditableCurvePoint: Equatable, Identifiable {
    var id: UUID
    var x: Double
    var y: Double
    var incomingSlope: Double?
    var outgoingSlope: Double?

    init(
        id: UUID = UUID(),
        x: Double,
        y: Double,
        incomingSlope: Double? = nil,
        outgoingSlope: Double? = nil
    ) {
        self.id = id
        self.x = x
        self.y = y
        self.incomingSlope = incomingSlope
        self.outgoingSlope = outgoingSlope
    }
}

@MainActor
final class InteractiveCurveEditorView: UIView {
    enum DragTarget {
        case point(UUID)
        case incomingHandle(UUID)
        case outgoingHandle(UUID)
    }

    var xDomain: ClosedRange<Double> = 0...1 { didSet { setNeedsDisplay() } }
    var yDomain: ClosedRange<Double> = 0...1 { didSet { setNeedsDisplay() } }
    var horizontalZero: Double? = nil { didSet { setNeedsDisplay() } }
    var lockFirstX = true
    var lockLastX = true
    var lockFirstY = false
    var lockLastY = false
    var minimumPointCount = 2
    var onChange: (([EditableCurvePoint]) -> Void)?
    var onSelectionChange: ((EditableCurvePoint?) -> Void)?

    private(set) var points: [EditableCurvePoint] = []
    private(set) var selectedID: UUID?
    private var dragTarget: DragTarget?
    private let graphInset = UIEdgeInsets(top: 18, left: 24, bottom: 24, right: 18)
    private let hitRadius: CGFloat = 20
    private let handleScreenDistance: CGFloat = 48

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 14
        layer.masksToBounds = true
        isMultipleTouchEnabled = false
        accessibilityLabel = "Interactive curve editor"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setPoints(_ newPoints: [EditableCurvePoint], notify: Bool = false) {
        points = normalized(newPoints)
        if let selectedID, !points.contains(where: { $0.id == selectedID }) {
            self.selectedID = nil
        }
        setNeedsDisplay()
        if notify { onChange?(points) }
    }

    func selectedPoint() -> EditableCurvePoint? {
        guard let selectedID else { return nil }
        return points.first(where: { $0.id == selectedID })
    }

    func deleteSelectedPoint() {
        guard points.count > minimumPointCount, let selectedID,
              let index = points.firstIndex(where: { $0.id == selectedID }) else { return }
        points.remove(at: index)
        self.selectedID = nil
        emitChange()
        onSelectionChange?(nil)
    }

    func addPoint(at dataPoint: CGPoint? = nil) {
        let x: Double
        let y: Double
        if let dataPoint {
            x = min(max(Double(dataPoint.x), xDomain.lowerBound), xDomain.upperBound)
            y = min(max(Double(dataPoint.y), yDomain.lowerBound), yDomain.upperBound)
        } else {
            x = (xDomain.lowerBound + xDomain.upperBound) * 0.5
            y = (yDomain.lowerBound + yDomain.upperBound) * 0.5
        }
        let point = EditableCurvePoint(x: x, y: y, incomingSlope: 0, outgoingSlope: 0)
        points.append(point)
        points = normalized(points)
        selectedID = point.id
        emitChange()
        onSelectionChange?(selectedPoint())
    }

    func sampledPoints(count: Int) -> [(x: Double, y: Double)] {
        guard points.count >= 2, count >= 2 else { return [] }
        return (0..<count).map { index in
            let p = Double(index) / Double(count - 1)
            let x = xDomain.lowerBound + p * (xDomain.upperBound - xDomain.lowerBound)
            return (x, value(at: x))
        }
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let graphRect = rect.inset(by: graphInset)
        guard graphRect.width > 1, graphRect.height > 1 else { return }

        drawGrid(context: context, rect: graphRect)
        drawAxes(context: context, rect: graphRect)
        drawCurve(context: context, rect: graphRect)
        drawPointsAndHandles(context: context, rect: graphRect)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        let graphRect = bounds.inset(by: graphInset)

        if touch.tapCount >= 2, graphRect.contains(location) {
            addPoint(at: dataPoint(from: location, in: graphRect))
            return
        }

        if let target = nearestHandle(to: location, in: graphRect) {
            dragTarget = target
            select(target)
            return
        }
        if let id = nearestPointID(to: location, in: graphRect) {
            selectedID = id
            dragTarget = .point(id)
            onSelectionChange?(selectedPoint())
            setNeedsDisplay()
        } else {
            selectedID = nil
            dragTarget = nil
            onSelectionChange?(nil)
            setNeedsDisplay()
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let dragTarget else { return }
        let location = touch.location(in: self)
        let graphRect = bounds.inset(by: graphInset)
        let data = dataPoint(from: location, in: graphRect)

        switch dragTarget {
        case .point(let id):
            guard let index = points.firstIndex(where: { $0.id == id }) else { return }
            let sortedBefore = points.sorted { $0.x < $1.x }
            let firstID = sortedBefore.first?.id
            let lastID = sortedBefore.last?.id
            var point = points[index]
            if !(lockFirstX && id == firstID) && !(lockLastX && id == lastID) {
                point.x = min(max(Double(data.x), xDomain.lowerBound), xDomain.upperBound)
            }
            if !(lockFirstY && id == firstID) && !(lockLastY && id == lastID) {
                point.y = min(max(Double(data.y), yDomain.lowerBound), yDomain.upperBound)
            }
            points[index] = point
            points = normalized(points)
            emitChange()
        case .incomingHandle(let id):
            updateSlope(for: id, handleData: data, incoming: true)
        case .outgoingHandle(let id):
            updateSlope(for: id, handleData: data, incoming: false)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        dragTarget = nil
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        dragTarget = nil
    }

    private func normalized(_ input: [EditableCurvePoint]) -> [EditableCurvePoint] {
        var output = input.map { point -> EditableCurvePoint in
            var point = point
            point.x = min(max(point.x, xDomain.lowerBound), xDomain.upperBound)
            point.y = min(max(point.y, yDomain.lowerBound), yDomain.upperBound)
            if !(point.incomingSlope?.isFinite ?? true) { point.incomingSlope = nil }
            if !(point.outgoingSlope?.isFinite ?? true) { point.outgoingSlope = nil }
            return point
        }.sorted { $0.x < $1.x }

        if output.count > 1 {
            for index in 1..<output.count where output[index].x <= output[index - 1].x {
                output[index].x = min(
                    xDomain.upperBound,
                    output[index - 1].x + max(0.0001, (xDomain.upperBound - xDomain.lowerBound) * 0.0001)
                )
            }
        }
        return output
    }

    private func emitChange() {
        setNeedsDisplay()
        onChange?(points)
        onSelectionChange?(selectedPoint())
    }

    private func select(_ target: DragTarget) {
        switch target {
        case .point(let id), .incomingHandle(let id), .outgoingHandle(let id): selectedID = id
        }
        onSelectionChange?(selectedPoint())
        setNeedsDisplay()
    }

    private func updateSlope(for id: UUID, handleData: CGPoint, incoming: Bool) {
        guard let index = points.firstIndex(where: { $0.id == id }) else { return }
        var point = points[index]
        let dx = Double(handleData.x) - point.x
        guard abs(dx) > 0.000001 else { return }
        let slope = (Double(handleData.y) - point.y) / dx
        if incoming { point.incomingSlope = slope } else { point.outgoingSlope = slope }
        points[index] = point
        emitChange()
    }

    private func drawGrid(context: CGContext, rect: CGRect) {
        context.saveGState()
        context.setStrokeColor(UIColor.separator.withAlphaComponent(0.28).cgColor)
        context.setLineWidth(0.5)
        for index in 0...4 {
            let p = CGFloat(index) / 4
            let x = rect.minX + rect.width * p
            let y = rect.minY + rect.height * p
            context.move(to: CGPoint(x: x, y: rect.minY))
            context.addLine(to: CGPoint(x: x, y: rect.maxY))
            context.move(to: CGPoint(x: rect.minX, y: y))
            context.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        context.strokePath()
        context.restoreGState()
    }

    private func drawAxes(context: CGContext, rect: CGRect) {
        guard let horizontalZero, yDomain.contains(horizontalZero) else { return }
        let y = screenPoint(x: xDomain.lowerBound, y: horizontalZero, in: rect).y
        context.saveGState()
        context.setStrokeColor(UIColor.label.withAlphaComponent(0.45).cgColor)
        context.setLineWidth(1)
        context.move(to: CGPoint(x: rect.minX, y: y))
        context.addLine(to: CGPoint(x: rect.maxX, y: y))
        context.strokePath()
        context.restoreGState()
    }

    private func drawCurve(context: CGContext, rect: CGRect) {
        guard points.count >= 2 else { return }
        let samples = sampledPoints(count: max(120, Int(rect.width)))
        guard let first = samples.first else { return }
        context.saveGState()
        context.setStrokeColor(UIColor.systemBlue.cgColor)
        context.setLineWidth(3)
        context.setLineJoin(.round)
        context.setLineCap(.round)
        context.move(to: screenPoint(x: first.x, y: first.y, in: rect))
        for sample in samples.dropFirst() {
            context.addLine(to: screenPoint(x: sample.x, y: sample.y, in: rect))
        }
        context.strokePath()
        context.restoreGState()
    }

    private func drawPointsAndHandles(context: CGContext, rect: CGRect) {
        let sorted = points.sorted { $0.x < $1.x }
        for point in sorted {
            let center = screenPoint(x: point.x, y: point.y, in: rect)
            let selected = point.id == selectedID
            if selected {
                if point.id != sorted.first?.id, let handle = handlePoint(for: point, incoming: true, in: rect) {
                    drawHandle(context: context, from: center, to: handle)
                }
                if point.id != sorted.last?.id, let handle = handlePoint(for: point, incoming: false, in: rect) {
                    drawHandle(context: context, from: center, to: handle)
                }
            }

            context.saveGState()
            context.setFillColor((selected ? UIColor.systemOrange : UIColor.systemBlue).cgColor)
            let radius: CGFloat = selected ? 7 : 5
            context.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            context.restoreGState()
        }
    }

    private func drawHandle(context: CGContext, from: CGPoint, to: CGPoint) {
        context.saveGState()
        context.setStrokeColor(UIColor.systemOrange.withAlphaComponent(0.8).cgColor)
        context.setLineWidth(1.2)
        context.move(to: from)
        context.addLine(to: to)
        context.strokePath()
        context.setFillColor(UIColor.systemOrange.cgColor)
        context.fillEllipse(in: CGRect(x: to.x - 5, y: to.y - 5, width: 10, height: 10))
        context.restoreGState()
    }

    private func nearestPointID(to location: CGPoint, in rect: CGRect) -> UUID? {
        points.min { lhs, rhs in
            distance(screenPoint(x: lhs.x, y: lhs.y, in: rect), location) < distance(screenPoint(x: rhs.x, y: rhs.y, in: rect), location)
        }.flatMap { point in
            distance(screenPoint(x: point.x, y: point.y, in: rect), location) <= hitRadius ? point.id : nil
        }
    }

    private func nearestHandle(to location: CGPoint, in rect: CGRect) -> DragTarget? {
        guard let selectedID, let point = points.first(where: { $0.id == selectedID }) else { return nil }
        let sorted = points.sorted { $0.x < $1.x }
        var candidates: [(DragTarget, CGPoint)] = []
        if point.id != sorted.first?.id, let incoming = handlePoint(for: point, incoming: true, in: rect) {
            candidates.append((.incomingHandle(point.id), incoming))
        }
        if point.id != sorted.last?.id, let outgoing = handlePoint(for: point, incoming: false, in: rect) {
            candidates.append((.outgoingHandle(point.id), outgoing))
        }
        return candidates.min { distance($0.1, location) < distance($1.1, location) }.flatMap {
            distance($0.1, location) <= hitRadius ? $0.0 : nil
        }
    }

    private func handlePoint(for point: EditableCurvePoint, incoming: Bool, in rect: CGRect) -> CGPoint? {
        let xScale = rect.width / CGFloat(max(0.000001, xDomain.upperBound - xDomain.lowerBound))
        let yScale = rect.height / CGFloat(max(0.000001, yDomain.upperBound - yDomain.lowerBound))
        let dataDX = Double(handleScreenDistance / xScale) * (incoming ? -1 : 1)
        let slope = incoming ? (point.incomingSlope ?? automaticSlope(for: point.id)) : (point.outgoingSlope ?? automaticSlope(for: point.id))
        let dataDY = slope * dataDX
        let handleX = point.x + dataDX
        let handleY = point.y + dataDY
        let screen = screenPoint(x: handleX, y: handleY, in: rect)
        let pointScreen = screenPoint(x: point.x, y: point.y, in: rect)
        let vector = CGPoint(x: screen.x - pointScreen.x, y: screen.y - pointScreen.y)
        let length = max(0.0001, sqrt(vector.x * vector.x + vector.y * vector.y))
        return CGPoint(
            x: pointScreen.x + vector.x / length * handleScreenDistance,
            y: pointScreen.y + vector.y / length * handleScreenDistance
        )
    }

    private func automaticSlope(for id: UUID) -> Double {
        guard let index = points.firstIndex(where: { $0.id == id }) else { return 0 }
        if index == 0, points.count > 1 { return secant(points[0], points[1]) }
        if index == points.count - 1 { return secant(points[index - 1], points[index]) }
        return (secant(points[index - 1], points[index]) + secant(points[index], points[index + 1])) * 0.5
    }

    private func value(at x: Double) -> Double {
        guard points.count >= 2 else { return points.first?.y ?? 0 }
        if x <= points[0].x { return points[0].y }
        if x >= points[points.count - 1].x { return points[points.count - 1].y }
        var segment = 0
        for index in 0..<(points.count - 1) where x >= points[index].x && x <= points[index + 1].x {
            segment = index
            break
        }
        let a = points[segment]
        let b = points[segment + 1]
        let duration = max(0.000001, b.x - a.x)
        let u = min(max((x - a.x) / duration, 0), 1)
        let m0 = a.outgoingSlope ?? automaticSlope(for: a.id)
        let m1 = b.incomingSlope ?? automaticSlope(for: b.id)
        let u2 = u * u
        let u3 = u2 * u
        return (2 * u3 - 3 * u2 + 1) * a.y +
            (u3 - 2 * u2 + u) * duration * m0 +
            (-2 * u3 + 3 * u2) * b.y +
            (u3 - u2) * duration * m1
    }

    private func secant(_ a: EditableCurvePoint, _ b: EditableCurvePoint) -> Double {
        (b.y - a.y) / max(0.000001, b.x - a.x)
    }

    private func screenPoint(x: Double, y: Double, in rect: CGRect) -> CGPoint {
        let px = (x - xDomain.lowerBound) / max(0.000001, xDomain.upperBound - xDomain.lowerBound)
        let py = (y - yDomain.lowerBound) / max(0.000001, yDomain.upperBound - yDomain.lowerBound)
        return CGPoint(
            x: rect.minX + CGFloat(px) * rect.width,
            y: rect.maxY - CGFloat(py) * rect.height
        )
    }

    private func dataPoint(from screen: CGPoint, in rect: CGRect) -> CGPoint {
        let px = min(max((screen.x - rect.minX) / max(1, rect.width), 0), 1)
        let py = min(max((rect.maxY - screen.y) / max(1, rect.height), 0), 1)
        return CGPoint(
            x: xDomain.lowerBound + Double(px) * (xDomain.upperBound - xDomain.lowerBound),
            y: yDomain.lowerBound + Double(py) * (yDomain.upperBound - yDomain.lowerBound)
        )
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}
#endif
