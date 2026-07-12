#if canImport(UIKit)
import Foundation
import UIKit
import ObjectiveC.runtime

@objc final class RuntimeResolver: NSObject {
    // EffectPickerCategoryVC is the per-category EFFECT GRID. Hooking it caused
    // Add Effects to crash. The category tiles live in EffectPickerMainVC.
    static let categoryControllerNames = [
        "AlightMotion.EffectPickerMainVC",
        "_TtC12AlightMotion18EffectPickerMainVC",
    ]

    static func categoryControllerClass() -> AnyClass? {
        for name in categoryControllerNames {
            if let cls = NSClassFromString(name) { return cls }
        }
        return nil
    }

    static func install() -> Bool {
        guard let cls = categoryControllerClass(),
              let original = class_getInstanceMethod(
                  cls,
                  #selector(UIViewController.viewDidAppear(_:))
              ),
              let replacement = class_getInstanceMethod(
                  UIViewController.self,
                  #selector(UIViewController.aemotion_viewDidAppear(_:))
              ) else {
            return false
        }

        method_exchangeImplementations(original, replacement)
        return true
    }
}

nonisolated(unsafe) private var proxyKey: UInt8 = 0

extension UIViewController {
    @objc fileprivate func aemotion_viewDidAppear(_ animated: Bool) {
        // After method exchange this calls EffectPickerMainVC's original method.
        self.aemotion_viewDidAppear(animated)

        guard String(describing: type(of: self)).contains("EffectPickerMainVC") else {
            return
        }

        // Do not replace a collection-view data source during its appearance
        // callbacks. Install on the next main-loop turn instead.
        DispatchQueue.main.async { [weak self] in
            self?.aemotion_installExtensionsCategoryIfNeeded()
        }
    }

    @MainActor
    private func aemotion_installExtensionsCategoryIfNeeded() {
        guard objc_getAssociatedObject(self, &proxyKey) == nil else { return }

        // This is the exact IBOutlet found in EffectPickerMainVC. Never use the
        // first UICollectionView recursively: the screen contains multiple lists.
        guard let collection = value(forKey: "categoriesCollectionView") as? UICollectionView,
              let dataSource = collection.dataSource,
              !(dataSource is CategoryCollectionProxy) else {
            return
        }

        let proxy = CategoryCollectionProxy(
            collectionView: collection,
            originalDataSource: dataSource,
            originalDelegate: collection.delegate,
            presenter: self
        )

        objc_setAssociatedObject(
            self,
            &proxyKey,
            proxy,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )

        collection.dataSource = proxy
        collection.delegate = proxy
        collection.reloadData()
        collection.collectionViewLayout.invalidateLayout()
    }
}
#endif
