#if canImport(UIKit)
import UIKit
import AEMotionExtensionsCore

@MainActor
struct HostEditingContract {
    let context: ContextualEditingContext
    let requiredTokens: [String]
    let valueControls: [UISlider]
    let previewView: UIView
    let selectionIdentity: ObjectIdentifier
    let anchorView: UIView

    var isSupported: Bool {
        !requiredTokens.isEmpty
            && !valueControls.isEmpty
            && valueControls.allSatisfy { !$0.isHidden && $0.isEnabled && $0.alpha > 0.01 }
            && previewView.window != nil
    }
}

@MainActor
protocol HostControlMutationAdapter: AnyObject {
    var context: ContextualEditingContext { get }
    var selectionIdentity: ObjectIdentifier { get }
    var ranges: [ClosedRange<Float>] { get }
    func snapshot() -> [Float]
    func apply(_ values: [Float]) -> Bool
    func restore(_ values: [Float])
    func invalidatePreview()
}

@MainActor
final class SliderControlMutationAdapter: HostControlMutationAdapter {
    let context: ContextualEditingContext
    let selectionIdentity: ObjectIdentifier
    let ranges: [ClosedRange<Float>]
    private let controls: [UISlider]
    private weak var previewView: UIView?

    init(contract: HostEditingContract) {
        context = contract.context
        selectionIdentity = contract.selectionIdentity
        controls = contract.valueControls
        ranges = contract.valueControls.map { $0.minimumValue...$0.maximumValue }
        previewView = contract.previewView
    }

    func snapshot() -> [Float] {
        controls.map(\.value)
    }

    func apply(_ values: [Float]) -> Bool {
        guard values.count == controls.count else { return false }
        for (control, value) in zip(controls, values) {
            control.setValue(min(max(value, control.minimumValue), control.maximumValue), animated: false)
            control.sendActions(for: .valueChanged)
        }
        invalidatePreview()
        return true
    }

    func restore(_ values: [Float]) {
        _ = apply(values)
    }

    func invalidatePreview() {
        previewView?.setNeedsLayout()
        previewView?.layoutIfNeeded()
        previewView?.setNeedsDisplay()
    }
}

@MainActor
final class HostEditingSession {
    let adapter: HostControlMutationAdapter
    let anchorView: UIView

    init(adapter: HostControlMutationAdapter, anchorView: UIView) {
        self.adapter = adapter
        self.anchorView = anchorView
    }
}

@MainActor
enum HostEditingContextBridge {
    private static let contextTokens: [ContextualEditingContext: Set<String>] = [
        .transform: ["move & transform", "transform", "position", "scale", "rotation"],
        .graph: ["graph", "easing", "bezier", "keyframe"],
        .speed: ["speed", "velocity", "time remap", "reverse", "freeze"],
        .effect: ["effect", "strength", "amount", "radius", "threshold"],
    ]

    static func resolve(context: ContextualEditingContext, in controller: UIViewController) -> HostEditingSession? {
        let views = descendants(of: controller.view)
        let searchable = views.compactMap(searchText(for:)).map(normalize)
        let matched = contextTokens[context, default: []].filter { token in
            searchable.contains { $0.contains(normalize(token)) }
        }
        let sliders = views.compactMap { $0 as? UISlider }.filter {
            !$0.isHidden && $0.alpha > 0.01 && $0.isEnabled && $0.window != nil
        }
        guard !matched.isEmpty, !sliders.isEmpty,
              let preview = previewCandidate(in: views, excluding: Set(sliders.map(ObjectIdentifier.init))),
              let anchor = sliders.first?.superview ?? controller.view else {
            return nil
        }
        let selectionObject: AnyObject = anchor
        let contract = HostEditingContract(
            context: context,
            requiredTokens: Array(matched).sorted(),
            valueControls: sliders,
            previewView: preview,
            selectionIdentity: ObjectIdentifier(selectionObject),
            anchorView: anchor
        )
        guard contract.isSupported else { return nil }
        return HostEditingSession(adapter: SliderControlMutationAdapter(contract: contract), anchorView: anchor)
    }

    static func resolveAll(in controller: UIViewController) -> [ContextualEditingContext: HostEditingSession] {
        Dictionary(uniqueKeysWithValues: ContextualEditingContext.allCases.compactMap { context in
            resolve(context: context, in: controller).map { (context, $0) }
        })
    }

    private static func descendants(of root: UIView) -> [UIView] {
        [root] + root.subviews.flatMap(descendants(of:))
    }

    private static func searchText(for view: UIView) -> String? {
        var parts: [String] = [String(describing: type(of: view))]
        if let identifier = view.accessibilityIdentifier { parts.append(identifier) }
        if let label = view.accessibilityLabel { parts.append(label) }
        if let label = view as? UILabel, let text = label.text { parts.append(text) }
        if let button = view as? UIButton, let title = button.title(for: .normal) { parts.append(title) }
        if let segmented = view as? UISegmentedControl {
            for index in 0..<segmented.numberOfSegments {
                if let title = segmented.titleForSegment(at: index) { parts.append(title) }
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    private static func normalize(_ value: String) -> String {
        value.lowercased().replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
    }

    private static func previewCandidate(in views: [UIView], excluding: Set<ObjectIdentifier>) -> UIView? {
        let visible = views.filter {
            !$0.isHidden && $0.alpha > 0.01 && $0.window != nil && !excluding.contains(ObjectIdentifier($0))
        }
        let named = visible.filter {
            let name = normalize(String(describing: type(of: $0))) + " " + normalize($0.accessibilityIdentifier ?? "")
            return name.contains("preview") || name.contains("canvas") || name.contains("viewer") || name.contains("render") || name.contains("player")
        }
        let candidates = named.isEmpty ? visible.filter {
            !($0 is UIControl) && !($0 is UIStackView) && !($0 is UITableView) && !($0 is UICollectionView)
        } : named
        return candidates
            .filter { $0.bounds.width * $0.bounds.height >= 10_000 }
            .max { lhs, rhs in lhs.bounds.width * lhs.bounds.height < rhs.bounds.width * rhs.bounds.height }
    }
}
#endif
