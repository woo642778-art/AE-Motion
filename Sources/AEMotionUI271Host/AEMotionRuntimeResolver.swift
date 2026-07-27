#if canImport(UIKit)
import UIKit
import ObjectiveC.runtime

@MainActor
enum AEMotionRuntimeResolver {
    private struct HookDefinition {
        let candidates: [String]
        let didAppearReplacement: Selector
        let willDisappearReplacement: Selector
    }

    private static let hooks: [HookDefinition] = [
        HookDefinition(
            candidates: [
                "AlightMotion.HomeVC", "_TtC12AlightMotion6HomeVC",
                "AlightMotion.HomeViewVC", "_TtC12AlightMotion10HomeViewVC",
            ],
            didAppearReplacement: #selector(UIViewController.aemotion271_homeVC_viewDidAppear(_:)),
            willDisappearReplacement: #selector(UIViewController.aemotion271_homeVC_viewWillDisappear(_:))
        ),
        HookDefinition(
            candidates: ["AlightMotion.ProjectsVC", "_TtC12AlightMotion10ProjectsVC"],
            didAppearReplacement: #selector(UIViewController.aemotion271_projectsVC_viewDidAppear(_:)),
            willDisappearReplacement: #selector(UIViewController.aemotion271_projectsVC_viewWillDisappear(_:))
        ),
        HookDefinition(
            candidates: ["AlightMotion.TemplatesVC", "_TtC12AlightMotion11TemplatesVC"],
            didAppearReplacement: #selector(UIViewController.aemotion271_templatesVC_viewDidAppear(_:)),
            willDisappearReplacement: #selector(UIViewController.aemotion271_templatesVC_viewWillDisappear(_:))
        ),
    ]

    static func install() -> Bool {
        var installedAny = false
        var installedClasses = Set<ObjectIdentifier>()
        for hook in hooks {
            guard let cls = firstClass(named: hook.candidates) else { continue }
            let identifier = ObjectIdentifier(cls)
            guard installedClasses.insert(identifier).inserted else { continue }
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
            installedAny = installedAny || didAppear || willDisappear
        }
        return installedAny
    }

    private static func firstClass(named candidates: [String]) -> AnyClass? {
        for name in candidates {
            if let cls = NSClassFromString(name) { return cls }
        }
        return nil
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

        let added = class_addMethod(
            cls,
            originalSelector,
            method_getImplementation(replacement),
            method_getTypeEncoding(replacement)
        )
        if added {
            class_replaceMethod(
                cls,
                replacementSelector,
                method_getImplementation(original),
                method_getTypeEncoding(original)
            )
        } else {
            method_exchangeImplementations(original, replacement)
        }
        return true
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
