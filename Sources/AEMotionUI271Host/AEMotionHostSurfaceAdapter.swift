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
    private var refreshGeneration = 0
    private lazy var projectCoordinator: AEMotionProjectActionCoordinator? = {
        guard let controller else { return nil }
        return AEMotionProjectActionCoordinator(hostController: controller)
    }()

    init(controller: UIViewController, role: AEMotionHostSurfaceRole) {
        self.controller = controller
        self.role = role
    }

    func prepareForRootPresentation() {
        guard let controller else { return }
        captureLegacyControls(in: controller.view)
        hideNativeRootChrome(from: controller)
        applyRootPresentation(to: controller)
        refreshGeneration += 1
        scheduleRefresh(generation: refreshGeneration, remaining: 24)
    }

    func refreshForRootPresentation() {
        guard let controller else { return }
        captureLegacyControls(in: controller.view)
        hideNativeRootChrome(from: controller)
        applyRootPresentation(to: controller)
    }

    func prepareForNonRootPresentation() {
        refreshGeneration += 1
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
        projectCoordinator?.perform(action, controls: legacyControls) ?? false
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

    private func applyRootPresentation(to controller: UIViewController) {
        switch role {
        case .home:
            hideOriginalHomeSurface(in: controller)
        case .projects, .templates:
            hideKnownLegacyOverlays(in: controller.view)
            normalizeHostSurface(in: controller.view)
        }
    }

    private func scheduleRefresh(generation: Int, remaining: Int) {
        guard remaining > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) { [weak self] in
            guard let self, generation == self.refreshGeneration else { return }
            self.refreshForRootPresentation()
            self.scheduleRefresh(generation: generation, remaining: remaining - 1)
        }
    }

    private func hideNativeRootChrome(from controller: UIViewController) {
        if let tabController = findTabController(from: controller) {
            tabController.tabBar.isHidden = true
            tabController.tabBar.isUserInteractionEnabled = false
        }
        if role == .home {
            controller.navigationController?.setNavigationBarHidden(true, animated: false)
        }
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
                  !view.aemotionHasAncestor(identifier: "aemotion.shell.root") else { continue }
            let identifier = (view.accessibilityIdentifier ?? "").lowercased()
            let label = (view.accessibilityLabel ?? "").lowercased()
            let title = ((control as? UIButton)?.title(for: .normal) ?? "").lowercased()
            let value = [identifier, label, title].joined(separator: " ")

            if value.contains("continue") { legacyControls[.continueEditing] = control }
            if value.contains("new") && value.contains("project") { legacyControls[.newProject] = control }
            if value.contains("import") { legacyControls[.importProject] = control }
            if value.contains("tutorial") { legacyControls[.tutorials] = control }
            if value.contains("template") { legacyControls[.templates] = control }
            if value.contains("3d-studio") || value.contains("3d studio") { legacyControls[.threeDStudio] = control }
            if value.contains("world-studio") || value.contains("world studio") { legacyControls[.worldStudio] = control }
            if value.contains("pre-comp") || value.contains("precomp") { legacyControls[.precompose] = control }
            if value.contains("track") { legacyControls[.tracking] = control }
            if value.contains("matte") { legacyControls[.matte] = control }
            if value.contains("depth") { legacyControls[.depthMap] = control }
            if value.contains("text") && identifier.contains("tool") { legacyControls[.textTool] = control }
            if value.contains("speed") { legacyControls[.speedRemap] = control }
            if value.contains("cutout") { legacyControls[.cutout] = control }
            if value.contains("preset") { legacyControls[.presetStudio] = control }
            if value.contains("camera") { legacyControls[.camera] = control }
            if value.contains("asset") { legacyControls[.assetLibrary] = control }
        }
    }

    private func hideKnownLegacyOverlays(in root: UIView) {
        var branches = Set<ObjectIdentifier>()
        var viewsToHide: [UIView] = []

        for view in root.aemotionAllDescendantsIncludingSelf() {
            guard view !== root,
                  !view.aemotionHasAncestor(identifier: "aemotion.shell.root") else { continue }
            let identifier = view.accessibilityIdentifier ?? ""
            let isLegacyHome = identifier.hasPrefix("aemotion.home.")
            let isLaunchOverlay = identifier == "aemotion.launch.overlay"
            guard isLegacyHome || isLaunchOverlay else { continue }
            guard let topLevelBranch = view.aemotionTopLevelBranch(under: root) else { continue }
            let key = ObjectIdentifier(topLevelBranch)
            if branches.insert(key).inserted {
                viewsToHide.append(topLevelBranch)
            }
        }

        for view in viewsToHide {
            view.isHidden = true
            view.isUserInteractionEnabled = false
            view.alpha = 0
        }
    }

    private func normalizeHostSurface(in root: UIView) {
        root.backgroundColor = AEMotionProductTheme.canvas
        for view in root.aemotionAllDescendantsIncludingSelf() {
            guard !view.aemotionHasAncestor(identifier: "aemotion.shell.root") else { continue }
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

    func aemotionHasAncestor(identifier: String) -> Bool {
        var candidate: UIView? = self
        while let view = candidate {
            if view.accessibilityIdentifier == identifier { return true }
            candidate = view.superview
        }
        return false
    }

    func aemotionTopLevelBranch(under root: UIView) -> UIView? {
        var candidate: UIView = self
        while let parent = candidate.superview, parent !== root {
            candidate = parent
        }
        return candidate.superview === root ? candidate : nil
    }
}
#endif
