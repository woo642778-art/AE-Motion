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
                  #selector(UIViewController.viewWillAppear(_:))
              ),
              let replacement = class_getInstanceMethod(
                  UIViewController.self,
                  #selector(UIViewController.aemotion_viewWillAppear(_:))
              ) else {
            return false
        }

        let originalSelector = #selector(UIViewController.viewWillAppear(_:))
        let replacementSelector = #selector(UIViewController.aemotion_viewWillAppear(_:))
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

nonisolated(unsafe) private var proxyKey: UInt8 = 0

extension UIViewController {
    @objc fileprivate func aemotion_viewWillAppear(_ animated: Bool) {
        // After swizzling this invokes EffectPickerMainVC's original implementation.
        self.aemotion_viewWillAppear(animated)

        guard String(describing: type(of: self)).contains("EffectPickerMainVC") else {
            return
        }

        // Prepare before the picker is visible so Extensions & Scripts does not pop
        // into the list after the first frame. A few bounded retries cover builds that
        // attach their collection-view outlets one run-loop turn later.
        aemotion_prepareEffectPicker(attempt: 0)
    }

    /// Reads an Objective-C-visible property or backing ivar without KVC.
    /// `value(forKey:)` throws NSUnknownKeyException when an outlet name differs
    /// between Alight Motion builds, so every optional private outlet is resolved
    /// through Objective-C runtime metadata instead.
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
    private func aemotion_prepareEffectPicker(attempt: Int) {
        aemotion_hideRecommendationStripIfPresent()
        let installed = aemotion_installExtensionsCategoryIfNeeded()
        if installed {
            aemotion_resizeCategoryCollectionIfNeeded()
            return
        }

        guard attempt < 4 else { return }
        let delay = 0.01 * Double(attempt + 1)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.aemotion_prepareEffectPicker(attempt: attempt + 1)
        }
    }

    /// Hides only the two known recommendation-carousel outlets. No view-tree
    /// heuristics are used, so unrelated Alight Motion collection views are untouched.
    @MainActor
    private func aemotion_hideRecommendationStripIfPresent() {
        if let recommendation = aemotion_runtimeObject(
            named: "recommendCollectionView"
        ) as? UICollectionView {
            recommendation.isHidden = true
            recommendation.alpha = 0
            recommendation.isUserInteractionEnabled = false
        }

        if let height = aemotion_runtimeObject(
            named: "recommendCollectionViewHeightConst"
        ) as? NSLayoutConstraint,
           abs(height.constant) > 0.5 {
            height.constant = 0
            UIView.performWithoutAnimation {
                view.setNeedsLayout()
                view.layoutIfNeeded()
            }
        }
    }

    @MainActor
    @discardableResult
    private func aemotion_installExtensionsCategoryIfNeeded() -> Bool {
        if objc_getAssociatedObject(self, &proxyKey) != nil {
            return true
        }

        guard let collection = aemotion_categoryCollection(),
              let dataSource = collection.dataSource else {
            return false
        }

        if dataSource is CategoryCollectionProxy {
            return true
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
        return true
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
