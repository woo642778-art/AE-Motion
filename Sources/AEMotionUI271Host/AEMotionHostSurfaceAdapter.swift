#if canImport(UIKit)
import UIKit

@MainActor
enum AEMotionHostSurfaceRole: String {
    case home
    case projects
    case templates
}

@MainActor
final class AEMotionHostSurfaceAdapter {
    private weak var controller: UIViewController?
    let role: AEMotionHostSurfaceRole

    init(controller: UIViewController, role: AEMotionHostSurfaceRole) {
        self.controller = controller
        self.role = role
    }

    func prepareForRootPresentation() {
        refreshForRootPresentation()
    }

    func refreshForRootPresentation() {
        guard let controller else { return }
        hideNativeRootChrome(from: controller)
        switch role {
        case .home:
            break
        case .projects, .templates:
            hideKnownLegacyOverlays(in: controller.view)
            normalizeHostSurface(in: controller.view)
        }
    }

    func prepareForNonRootPresentation() {}

    private func hideNativeRootChrome(from controller: UIViewController) {
        controller.tabBarController?.tabBar.isHidden = true
        controller.tabBarController?.tabBar.isUserInteractionEnabled = false
    }

    private func hideKnownLegacyOverlays(in root: UIView) {
        var hiddenBranches = Set<ObjectIdentifier>()
        for view in allDescendantsIncludingSelf(root) {
            guard view !== root else { continue }
            let identifier = view.accessibilityIdentifier ?? ""
            let isOwnedLegacyOverlay = identifier.hasPrefix("aemotion.home.")
                || identifier == "aemotion.launch.overlay"
            guard isOwnedLegacyOverlay,
                  let branch = topLevelBranch(for: view, under: root),
                  hiddenBranches.insert(ObjectIdentifier(branch)).inserted else {
                continue
            }
            branch.isHidden = true
            branch.isUserInteractionEnabled = false
            branch.alpha = 0
        }
    }

    private func normalizeHostSurface(in root: UIView) {
        root.backgroundColor = AEMotionProductTheme.canvas
        for view in allDescendantsIncludingSelf(root) {
            switch view {
            case let table as UITableView:
                table.backgroundColor = AEMotionProductTheme.canvas
                table.backgroundView?.backgroundColor = AEMotionProductTheme.canvas
            case let collection as UICollectionView:
                collection.backgroundColor = AEMotionProductTheme.canvas
                collection.backgroundView?.backgroundColor = AEMotionProductTheme.canvas
            case let scroll as UIScrollView:
                if scroll.backgroundColor == nil || scroll.backgroundColor == .clear {
                    scroll.backgroundColor = AEMotionProductTheme.canvas
                }
            case let label as UILabel:
                normalizeTextContrast(label)
            case let textView as UITextView where !textView.isEditable:
                textView.textColor = AEMotionProductTheme.primaryText
            case let button as UIButton where button.configuration == nil:
                button.setTitleColor(AEMotionProductTheme.primaryText, for: .normal)
            default:
                break
            }
        }
    }

    private func normalizeTextContrast(_ label: UILabel) {
        guard !label.isHidden, label.alpha > 0.01 else { return }
        if let attributed = label.attributedText, attributed.length > 0 {
            let mutable = NSMutableAttributedString(attributedString: attributed)
            mutable.addAttribute(
                .foregroundColor,
                value: label.isEnabled
                    ? AEMotionProductTheme.primaryText
                    : AEMotionProductTheme.tertiaryText,
                range: NSRange(location: 0, length: mutable.length)
            )
            label.attributedText = mutable
        } else {
            label.textColor = label.isEnabled
                ? AEMotionProductTheme.primaryText
                : AEMotionProductTheme.tertiaryText
        }
    }

    private func allDescendantsIncludingSelf(_ root: UIView) -> [UIView] {
        var result: [UIView] = [root]
        var index = 0
        while index < result.count {
            result.append(contentsOf: result[index].subviews)
            index += 1
        }
        return result
    }

    private func topLevelBranch(for view: UIView, under root: UIView) -> UIView? {
        var candidate = view
        while let parent = candidate.superview, parent !== root {
            candidate = parent
        }
        return candidate.superview === root ? candidate : nil
    }
}
#endif
