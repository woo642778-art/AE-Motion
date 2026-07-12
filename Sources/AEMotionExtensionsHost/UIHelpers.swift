#if canImport(UIKit)
import UIKit

@MainActor
enum ExtensionUI {
    static func field(_ placeholder: String, value: String = "") -> UITextField {
        let field = UITextField()
        field.placeholder = placeholder
        field.text = value
        field.borderStyle = .roundedRect
        field.keyboardType = .decimalPad
        field.clearButtonMode = .whileEditing
        return field
    }

    static func label(_ text: String, style: UIFont.TextStyle = .body) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: style)
        label.numberOfLines = 0
        return label
    }

    static func button(_ title: String, action: UIAction) -> UIButton {
        let button = UIButton(type: .system, primaryAction: action)
        var configuration = UIButton.Configuration.filled()
        configuration.title = title
        configuration.cornerStyle = .medium
        button.configuration = configuration
        return button
    }

    static func stack(_ views: [UIView], spacing: CGFloat = 12) -> UIStackView {
        let stack = UIStackView(arrangedSubviews: views)
        stack.axis = .vertical
        stack.spacing = spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    static func installScrollStack(_ stack: UIStackView, in controller: UIViewController) {
        let scroll = UIScrollView()
        scroll.alwaysBounceVertical = true
        scroll.keyboardDismissMode = .interactive
        scroll.translatesAutoresizingMaskIntoConstraints = false
        controller.view.addSubview(scroll)
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: controller.view.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -40),
        ])
    }

    static func share(text: String, from controller: UIViewController, source: UIView? = nil) {
        let share = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        if let popover = share.popoverPresentationController {
            popover.sourceView = source ?? controller.view
            popover.sourceRect = (source ?? controller.view).bounds
        }
        controller.present(share, animated: true)
    }

    static func share(fileURL: URL, from controller: UIViewController, source: UIView? = nil) {
        let share = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
        if let popover = share.popoverPresentationController {
            popover.sourceView = source ?? controller.view
            popover.sourceRect = (source ?? controller.view).bounds
        }
        controller.present(share, animated: true)
    }

    static func alert(title: String, message: String, from controller: UIViewController) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        controller.present(alert, animated: true)
    }
}

final class CurveGraphView: UIView {
    var points: [(x: Double, y: Double)] = [] { didSet { setNeedsDisplay() } }
    var horizontalZero: Double = 0 { didSet { setNeedsDisplay() } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 12
        layer.masksToBounds = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(), points.count >= 2 else { return }
        let inset = rect.insetBy(dx: 14, dy: 14)
        let minX = points.map(\.x).min() ?? 0
        let maxX = points.map(\.x).max() ?? 1
        var minY = points.map(\.y).min() ?? 0
        var maxY = points.map(\.y).max() ?? 1
        minY = min(minY, horizontalZero)
        maxY = max(maxY, horizontalZero)
        if abs(maxX - minX) < 0.0001 { return }
        if abs(maxY - minY) < 0.0001 { maxY = minY + 1 }

        func map(_ point: (x: Double, y: Double)) -> CGPoint {
            let x = inset.minX + CGFloat((point.x - minX) / (maxX - minX)) * inset.width
            let y = inset.maxY - CGFloat((point.y - minY) / (maxY - minY)) * inset.height
            return CGPoint(x: x, y: y)
        }

        context.setStrokeColor(UIColor.separator.cgColor)
        context.setLineWidth(1)
        let zeroY = map((minX, horizontalZero)).y
        context.move(to: CGPoint(x: inset.minX, y: zeroY))
        context.addLine(to: CGPoint(x: inset.maxX, y: zeroY))
        context.strokePath()

        context.setStrokeColor(UIColor.systemBlue.cgColor)
        context.setLineWidth(2.5)
        context.setLineJoin(.round)
        context.setLineCap(.round)
        context.move(to: map(points[0]))
        for point in points.dropFirst() { context.addLine(to: map(point)) }
        context.strokePath()

        context.setFillColor(UIColor.systemBlue.cgColor)
        for point in points where point.x == minX || point.x == maxX {
            let p = map(point)
            context.fillEllipse(in: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6))
        }
    }
}
#endif
