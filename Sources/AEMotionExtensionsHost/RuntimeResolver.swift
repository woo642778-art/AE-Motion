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

    /// Reads an Objective-C-visible property or backing ivar without KVC.
    /// `value(forKey:)` throws NSUnknownKeyException when an outlet name differs
    /// between Alight Motion builds; that was the v1.5.3 Add Effects crash.
    @MainActor
    private func aemotion_runtimeObject(named name: String) -> AnyObject? {
        let selector = NSSelectorFromString(name)
        if responds(to: selector),
           let value = perform(selector)?.takeUnretainedValue() {
            return value
        }

        let candidates = [name, "_\(name)"]
        var currentClass: AnyClass? = type(of: self)
        while let cls = currentClass {
            for candidate in candidates {
                if let ivar = class_getInstanceVariable(cls, candidate),
                   let value = object_getIvar(self, ivar) {
                    return value as AnyObject
                }
            }
            currentClass = class_getSuperclass(cls)
        }
        return nil
    }

    @MainActor
    private func aemotion_categoryCollection() -> UICollectionView? {
        aemotion_runtimeObject(named: "categoriesCollectionView") as? UICollectionView
    }

    @MainActor
    private func aemotion_installExtensionsCategoryIfNeeded() {
        guard objc_getAssociatedObject(self, &proxyKey) == nil else {
            aemotion_resizeCategoryCollectionIfNeeded()
            return
        }

        guard let collection = aemotion_categoryCollection(),
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

        DispatchQueue.main.async { [weak self] in
            self?.aemotion_resizeCategoryCollectionIfNeeded()
        }
    }

    @MainActor
    private func aemotion_resizeCategoryCollectionIfNeeded() {
        guard let collection = aemotion_categoryCollection() else { return }

        collection.collectionViewLayout.invalidateLayout()
        collection.layoutIfNeeded()

        let contentHeight = ceil(collection.collectionViewLayout.collectionViewContentSize.height)
        guard contentHeight.isFinite, contentHeight > 0 else { return }

        if let heightConstraint = aemotion_runtimeObject(
            named: "categoriesCollectionViewHeightConst"
        ) as? NSLayoutConstraint {
            if abs(heightConstraint.constant - contentHeight) > 0.5 {
                heightConstraint.constant = contentHeight
                UIView.performWithoutAnimation {
                    view.setNeedsLayout()
                    view.layoutIfNeeded()
                }
            }
        } else {
            // The outlet is not present in every app build. Do not use KVC and do
            // not crash; allow the added row to be reached by scrolling instead.
            collection.isScrollEnabled = true
            collection.alwaysBounceVertical = false
            collection.showsVerticalScrollIndicator = true
        }
    }
}
#endif
