#if canImport(UIKit)
import UIKit
import AEMotionExtensionsCore

@MainActor
enum AEMotionHostSurfaceRole: String {
    case home
    case projects
    case templates

    var tab: HomeShellTab {
        switch self {
        case .home: return .home
        case .projects: return .projects
        case .templates: return .templates
        }
    }
}

@MainActor
final class AEMotionHostSurfaceAdapter {
    private struct HiddenViewState {
        let view: UIView
        let wasHidden: Bool
        let wasUserInteractionEnabled: Bool
    }

    private weak var controller: UIViewController?
    let role: AEMotionHostSurfaceRole
    private var hiddenHomeViews: [HiddenViewState] = []
    private var legacyControls: [AEMotionHomeAction: UIControl] = [:]
    private var hasPreparedHome = false

    init(controller: UIViewController, role: AEMotionHostSurfaceRole) {
        self.controller = controller
        self.role = role
    }

    func prepareForRootPresentation() {
        guard let controller else { return }
        switch role {
        case .home:
            captureLegacyControls(in: controller.view)
            hideOriginalHomeSurface(in: controller)
        case .projects, .templates:
            hideKnownLegacyOverlays(in: controller.view)
            normalizeHostSurface(in: controller.view)
        }
    }

    func restoreOriginalHomeSurface() {
        guard role == .home else { return }
        for state in hiddenHomeViews {
            state.view.isHidden = state.wasHidden
            state.view.isUserInteractionEnabled = state.wasUserInteractionEnabled
        }
        hiddenHomeViews.removeAll()
        hasPreparedHome = false
    }

    @discardableResult
    func perform(_ action: AEMotionHomeAction) -> Bool {
        if let control = legacyControls[action] {
            control.sendActions(for: .touchUpInside)
            return true
        }
        return false
    }

    @discardableResult
    func route(to tab: HomeShellTab) -> Bool {
        guard let controller else { return false }
        if tab == role.tab { return true }
        guard let tabController = findTabController(from: controller) else { return false }

        let keywords: [String]
        switch tab {
        case .home: keywords = ["home"]
        case .tutorials: keywords = ["tutorial", "learn"]
        case .projects: keywords = ["project"]
        case .templates: keywords = ["template"]
        case .create: return false
        }

        if let index = tabController.viewControllers?.firstIndex(where: { candidate in
            let values = [
                candidate.tabBarItem.title,
                candidate.tabBarItem.accessibilityLabel,
                String(describing: type(of: candidate)),
            ].compactMap { $0?.lowercased() }
            return keywords.contains { keyword in values.contains { $0.contains(keyword) } }
        }) {
            tabController.selectedIndex = index
            return true
        }

        let fallback: Int
        switch tab {
        case .home: fallback = 0
        case .tutorials: fallback = 1
        case .projects: fallback = 3
        case .templates: fallback = 4
        case .create: return false
        }
        guard fallback < (tabController.viewControllers?.count ?? 0) else { return false }
        tabController.selectedIndex = fallback
        return true
    }

    private func hideOriginalHomeSurface(in controller: UIViewController) {
        guard !hasPreparedHome else { return }
        hasPreparedHome = true
        hiddenHomeViews = controller.view.subviews.compactMap { subview in
            guard subview.accessibilityIdentifier != "aemotion.shell.root" else { return nil }
            let state = HiddenViewState(
                view: subview,
                wasHidden: subview.isHidden,
                wasUserInteractionEnabled: subview.isUserInteractionEnabled
            )
            subview.isHidden = true
            subview.isUserInteractionEnabled = false
            return state
        }
        controller.view.backgroundColor = AEMotionProductTheme.canvas
    }

    private func captureLegacyControls(in root: UIView) {
        for view in root.aemotionAllDescendantsIncludingSelf() {
            guard let control = view as? UIControl,
                  let identifier = view.accessibilityIdentifier else { continue }
            switch identifier {
            case "aemotion.home.continue": legacyControls[.continueEditing] = control
            case "aemotion.home.new": legacyControls[.newProject] = control
            case "aemotion.home.import": legacyControls[.importProject] = control
            case "aemotion.home.tutorial": legacyControls[.tutorials] = control
            case "aemotion.home.templates": legacyControls[.templates] = control
            case "aemotion.home.3d-studio": legacyControls[.threeDStudio] = control
            case "aemotion.home.world-studio": legacyControls[.worldStudio] = control
            default:
                guard identifier.hasPrefix("aemotion.home.tool.") else { continue }
                let suffix = identifier.lowercased()
                if suffix.contains("speed") { legacyControls[.speedRemap] = control }
                else if suffix.contains("cutout") { legacyControls[.cutout] = control }
                else if suffix.contains("depth") { legacyControls[.depthMap] = control }
                else if suffix.contains("preset") { legacyControls[.presetStudio] = control }
                else if suffix.contains("camera") { legacyControls[.camera] = control }
                else if suffix.contains("asset") { legacyControls[.assetLibrary] = control }
            }
        }
    }

    private func hideKnownLegacyOverlays(in root: UIView) {
        let rootArea = max(root.bounds.width * root.bounds.height, 1)
        for view in root.aemotionAllDescendantsIncludingSelf() {
            guard view !== root,
                  let identifier = view.accessibilityIdentifier,
                  identifier.hasPrefix("aemotion.") else { continue }
            let converted = view.convert(view.bounds, to: root)
            let coverage = max(converted.width * converted.height, 0) / rootArea
            let isKnownOverlay = identifier == "aemotion.launch.overlay"
                || identifier == "aemotion.home.surface"
                || identifier == "aemotion.shell.root"
                || coverage >= 0.72
            guard isKnownOverlay else { continue }
            view.isHidden = true
            view.isUserInteractionEnabled = false
        }
    }

    private func normalizeHostSurface(in root: UIView) {
        root.backgroundColor = AEMotionProductTheme.canvas
        for view in root.aemotionAllDescendantsIncludingSelf() {
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
            case let textView as UITextView:
                if textView.isEditable == false {
                    textView.textColor = AEMotionProductTheme.primaryText
                }
            case let button as UIButton:
                if button.configuration == nil {
                    button.setTitleColor(AEMotionProductTheme.primaryText, for: .normal)
                }
            default:
                break
            }
        }
    }

    private func normalizeTextContrast(_ label: UILabel) {
        if let attributed = label.attributedText, attributed.length > 0 {
            let mutable = NSMutableAttributedString(attributedString: attributed)
            mutable.addAttribute(
                .foregroundColor,
                value: label.isEnabled ? AEMotionProductTheme.primaryText : AEMotionProductTheme.tertiaryText,
                range: NSRange(location: 0, length: mutable.length)
            )
            label.attributedText = mutable
        } else {
            label.textColor = label.isEnabled
                ? AEMotionProductTheme.primaryText
                : AEMotionProductTheme.tertiaryText
        }
    }

    private func findTabController(from controller: UIViewController) -> UITabBarController? {
        if let tab = controller.tabBarController { return tab }
        var parent = controller.parent
        while let current = parent {
            if let tab = current as? UITabBarController { return tab }
            parent = current.parent
        }
        return nil
    }
}

private extension UIView {
    func aemotionAllDescendantsIncludingSelf() -> [UIView] {
        var result: [UIView] = [self]
        var index = 0
        while index < result.count {
            result.append(contentsOf: result[index].subviews)
            index += 1
        }
        return result
    }
}
#endif
