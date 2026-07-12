#if canImport(UIKit)
import Foundation
import UIKit
import ObjectiveC.runtime

@objc final class RuntimeResolver: NSObject {
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
        // After swizzling this invokes EffectPickerMainVC's original implementation.
        self.aemotion_viewDidAppear(animated)

        guard String(describing: type(of: self)).contains("EffectPickerMainVC") else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.aemotion_installExtensionsCategoryIfNeeded()
        }
    }

    @MainActor
    private func aemotion_installExtensionsCategoryIfNeeded() {
        guard objc_getAssociatedObject(self, &proxyKey) == nil else {
            aemotion_resizeCategoryCollectionIfNeeded()
            return
        }

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

        // EffectPickerMainVC keeps a fixed height constraint sized for the stock
        // category count. Adding one item pushes Repeat and later categories into
        // a clipped extra row, which looks like Repeat was replaced. Recalculate
        // the collection height after the new item is laid out so every original
        // category remains visible.
        DispatchQueue.main.async { [weak self] in
            self?.aemotion_resizeCategoryCollectionIfNeeded()
        }
    }

    @MainActor
    private func aemotion_resizeCategoryCollectionIfNeeded() {
        guard let collection = value(forKey: "categoriesCollectionView") as? UICollectionView else {
            return
        }

        collection.collectionViewLayout.invalidateLayout()
        collection.layoutIfNeeded()

        let contentHeight = ceil(collection.collectionViewLayout.collectionViewContentSize.height)
        guard contentHeight > 0 else { return }

        if let heightConstraint = value(forKey: "categoriesCollectionViewHeightConst") as? NSLayoutConstraint {
            if abs(heightConstraint.constant - contentHeight) > 0.5 {
                heightConstraint.constant = contentHeight
                view.setNeedsLayout()
                view.layoutIfNeeded()
            }
        } else {
            // Fail-safe for builds where the outlet name changes: allow the
            // collection itself to scroll rather than clipping displaced items.
            collection.isScrollEnabled = true
        }
    }
}
#endif
