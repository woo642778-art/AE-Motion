#if canImport(UIKit)
import Foundation
import UIKit
import ObjectiveC.runtime

@MainActor
enum WatermarkStateRefresh {
    private static let controllerNames = [
        "AlightMotion.ProjectEditVC",
        "_TtC12AlightMotion13ProjectEditVC",
        "AlightMotion.ExportVC",
        "_TtC12AlightMotion8ExportVC",
        "AlightMotion.ExportPreviewVC",
        "_TtC12AlightMotion15ExportPreviewVC",
    ]

    private static var observerInstalled = false
    private static var installedClasses = Set<ObjectIdentifier>()
    private static var observerToken: NSObjectProtocol?

    static func start() {
        if !observerInstalled {
            observerInstalled = true
            observerToken = NotificationCenter.default.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    installAvailableHooks()
                    refreshVisibleHierarchy()
                }
            }
        }
        installAvailableHooks()
    }

    static func refreshVisibleHierarchy() {
        let keyWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
        guard let root = keyWindow?.rootViewController else { return }
        refresh(in: root)
    }

    static func refresh(in controller: UIViewController) {
        refreshControllerTree(controller)
    }

    private static func installAvailableHooks() {
        for name in controllerNames {
            guard let cls = NSClassFromString(name) else { continue }
            installViewDidAppearHook(on: cls)
        }
    }

    private static func installViewDidAppearHook(on cls: AnyClass) {
        let classID = ObjectIdentifier(cls)
        guard !installedClasses.contains(classID) else { return }

        let selector = #selector(UIViewController.viewDidAppear(_:))
        guard let originalMethod = class_getInstanceMethod(cls, selector),
              let typeEncoding = method_getTypeEncoding(originalMethod) else {
            return
        }
        let originalIMP = method_getImplementation(originalMethod)

        let block: @convention(block) (AnyObject, Bool) -> Void = { object, animated in
            typealias OriginalImplementation = @convention(c) (AnyObject, Selector, Bool) -> Void
            let original = unsafeBitCast(originalIMP, to: OriginalImplementation.self)
            original(object, selector, animated)

            guard let controller = object as? UIViewController else { return }
            Task { @MainActor in
                refresh(in: controller)
            }
        }

        let replacementIMP = imp_implementationWithBlock(block)
        class_replaceMethod(cls, selector, replacementIMP, typeEncoding)
        installedClasses.insert(classID)
    }

    private static func refreshControllerTree(_ controller: UIViewController) {
        invokeRefreshSelectors(on: controller)

        for child in controller.children {
            refreshControllerTree(child)
        }
        if let presented = controller.presentedViewController {
            refreshControllerTree(presented)
        }
    }

    private static func invokeRefreshSelectors(on object: NSObject) {
        for selectorName in ["updateWatermarkView", "refreshWatermark", "reloadWatermark"] {
            let selector = NSSelectorFromString(selectorName)
            guard object.responds(to: selector) else { continue }
            _ = object.perform(selector)
        }

        if let viewController = object as? UIViewController {
            viewController.view.setNeedsLayout()
            viewController.view.layoutIfNeeded()
        }
    }
}
#endif
