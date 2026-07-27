#if canImport(UIKit)
import UIKit
import ObjectiveC.runtime

@MainActor
enum AEMotionRuntimeResolver {
    private enum HookRole: CaseIterable, Hashable {
        case home
        case projects
        case templates

        var surfaceRole: AEMotionHostSurfaceRole {
            switch self {
            case .home: return .home
            case .projects: return .projects
            case .templates: return .templates
            }
        }
    }

    private struct HookDefinition {
        let role: HookRole
        let candidates: [String]
        let didAppearReplacement: Selector
        let willDisappearReplacement: Selector
    }

    private static let hooks: [HookDefinition] = [
        HookDefinition(
            role: .home,
            candidates: [
                "AlightMotion.HomeVC", "_TtC12AlightMotion6HomeVC",
                "AlightMotion.HomeViewVC", "_TtC12AlightMotion10HomeViewVC",
            ],
            didAppearReplacement: #selector(UIViewController.aemotion271_homeVC_viewDidAppear(_:)),
            willDisappearReplacement: #selector(UIViewController.aemotion271_homeVC_viewWillDisappear(_:))
        ),
        HookDefinition(
            role: .projects,
            candidates: [
                "AlightMotion.ProjectsVC", "_TtC12AlightMotion10ProjectsVC",
                "AlightMotion.ProjectsListVC", "_TtC12AlightMotion14ProjectsListVC",
            ],
            didAppearReplacement: #selector(UIViewController.aemotion271_projectsVC_viewDidAppear(_:)),
            willDisappearReplacement: #selector(UIViewController.aemotion271_projectsVC_viewWillDisappear(_:))
        ),
        HookDefinition(
            role: .templates,
            candidates: [
                "AlightMotion.TemplatesListVC", "_TtC12AlightMotion15TemplatesListVC",
                "AlightMotion.TemplatesShowcaseVC", "_TtC12AlightMotion19TemplatesShowcaseVC",
            ],
            didAppearReplacement: #selector(UIViewController.aemotion271_templatesVC_viewDidAppear(_:)),
            willDisappearReplacement: #selector(UIViewController.aemotion271_templatesVC_viewWillDisappear(_:))
        ),
    ]

    private static var installedClasses = Set<ObjectIdentifier>()
    private static var installedRoles = Set<HookRole>()

    static var hasInstalledRequiredRootHooks: Bool {
        Set(HookRole.allCases).isSubset(of: installedRoles)
    }

    @discardableResult
    static func install() -> Bool {
        var installedAny = false

        for hook in hooks {
            for candidate in hook.candidates {
                guard let cls = NSClassFromString(candidate) else { continue }
                let identifier = ObjectIdentifier(cls)
                if installedClasses.contains(identifier) {
                    installedRoles.insert(hook.role)
                    continue
                }

                let didAppear = installHook(
                    on: cls,
                    originalSelector: #selector(UIViewController.viewDidAppear(_:)),
                    replacementSelector: hook.didAppearReplacement
                )
                let willDisappear = installHook(
                    on: cls,
                    originalSelector: #selector(UIViewController.viewWillDisappear(_:)),
                    replacementSelector: hook.willDisappearReplacement
                )
                guard didAppear && willDisappear else { continue }

                installedClasses.insert(identifier)
                installedRoles.insert(hook.role)
                installedAny = true
            }
        }

        refreshVisibleRootSurfaces()
        return installedAny
    }

    static func refreshVisibleRootSurfaces() {
        for window in activeWindows() where !window.isHidden && window.alpha > 0.01 {
            guard let root = window.rootViewController else { continue }
            for controller in visibleControllerTree(from: root) {
                guard controller.isViewLoaded, controller.view.window != nil,
                      let role = role(for: controller) else { continue }
                controller.aemotion271Prepare(role: role.surfaceRole)
            }
        }
    }

    private static func installHook(
        on cls: AnyClass,
        originalSelector: Selector,
        replacementSelector: Selector
    ) -> Bool {
        guard let original = class_getInstanceMethod(cls, originalSelector),
              let replacement = class_getInstanceMethod(UIViewController.self, replacementSelector) else {
            return false
        }

        let originalIMP = method_getImplementation(original)
        let originalTypes = method_getTypeEncoding(original)
        let replacementIMP = method_getImplementation(replacement)
        let replacementTypes = method_getTypeEncoding(replacement)

        guard class_addMethod(
            cls,
            replacementSelector,
            originalIMP,
            originalTypes
        ) else {
            return false
        }

        class_replaceMethod(
            cls,
            originalSelector,
            replacementIMP,
            replacementTypes
        )
        return true
    }

    private static func role(for controller: UIViewController) -> HookRole? {
        for hook in hooks {
            for candidate in hook.candidates {
                guard let cls = NSClassFromString(candidate) else { continue }
                if controller.isKind(of: cls) { return hook.role }
            }
        }
        return nil
    }

    private static func activeWindows() -> [UIWindow] {
        var result: [UIWindow] = []
        var seen = Set<ObjectIdentifier>()
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows where seen.insert(ObjectIdentifier(window)).inserted {
                result.append(window)
            }
        }
        return result
    }

    private static func visibleControllerTree(from root: UIViewController) -> [UIViewController] {
        var result: [UIViewController] = []
        var queue: [UIViewController] = [root]
        var seen = Set<ObjectIdentifier>()

        while !queue.isEmpty {
            let controller = queue.removeFirst()
            guard seen.insert(ObjectIdentifier(controller)).inserted else { continue }
            result.append(controller)

            if let presented = controller.presentedViewController,
               !presented.isBeingDismissed {
                queue.append(presented)
            }
            if let navigation = controller as? UINavigationController,
               let visible = navigation.visibleViewController {
                queue.append(visible)
            }
            if let tab = controller as? UITabBarController,
               let selected = tab.selectedViewController {
                queue.append(selected)
            }
            for child in controller.children where child.viewIfLoaded?.window != nil {
                queue.append(child)
            }
        }
        return result
    }
}

nonisolated(unsafe) private var aemotion271AdapterKey: UInt8 = 0

@MainActor
private extension UIViewController {
    var aemotion271SurfaceAdapter: AEMotionHostSurfaceAdapter? {
        get { objc_getAssociatedObject(self, &aemotion271AdapterKey) as? AEMotionHostSurfaceAdapter }
        set { objc_setAssociatedObject(self, &aemotion271AdapterKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    func aemotion271Prepare(role: AEMotionHostSurfaceRole) {
        let adapter: AEMotionHostSurfaceAdapter
        if let existing = aemotion271SurfaceAdapter, existing.role == role {
            adapter = existing
        } else {
            adapter = AEMotionHostSurfaceAdapter(controller: self, role: role)
            aemotion271SurfaceAdapter = adapter
        }
        adapter.prepareForRootPresentation()

        let shell = AEMotionShellViewController.shared
        shell.routeHandler = { [weak adapter] tab in _ = adapter?.route(to: tab) }
        shell.actionHandler = { [weak adapter] action in _ = adapter?.perform(action) }
        shell.attach(to: self, tab: role.tab, showsHomeContent: role == .home)
    }

    func aemotion271WillLeaveRoot() {
        aemotion271SurfaceAdapter?.prepareForNonRootPresentation()
        AEMotionShellViewController.shared.openNonRoot(.detail)
    }

    @objc func aemotion271_homeVC_viewDidAppear(_ animated: Bool) {
        aemotion271_homeVC_viewDidAppear(animated)
        aemotion271Prepare(role: .home)
    }

    @objc func aemotion271_homeVC_viewWillDisappear(_ animated: Bool) {
        aemotion271_homeVC_viewWillDisappear(animated)
        aemotion271WillLeaveRoot()
    }

    @objc func aemotion271_projectsVC_viewDidAppear(_ animated: Bool) {
        aemotion271_projectsVC_viewDidAppear(animated)
        aemotion271Prepare(role: .projects)
    }

    @objc func aemotion271_projectsVC_viewWillDisappear(_ animated: Bool) {
        aemotion271_projectsVC_viewWillDisappear(animated)
        aemotion271WillLeaveRoot()
    }

    @objc func aemotion271_templatesVC_viewDidAppear(_ animated: Bool) {
        aemotion271_templatesVC_viewDidAppear(animated)
        aemotion271Prepare(role: .templates)
    }

    @objc func aemotion271_templatesVC_viewWillDisappear(_ animated: Bool) {
        aemotion271_templatesVC_viewWillDisappear(animated)
        aemotion271WillLeaveRoot()
    }
}
#endif
