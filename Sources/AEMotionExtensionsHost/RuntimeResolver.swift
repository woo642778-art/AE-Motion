#if canImport(UIKit)
import Foundation
import UIKit
import ObjectiveC.runtime
import AEMotionExtensionsCore

@objc final class RuntimeResolver: NSObject {
    static let categoryControllerNames = [
        "AlightMotion.EffectPickerMainVC",
        "_TtC12AlightMotion18EffectPickerMainVC",
    ]

    static let projectEditorControllerNames = [
        "AlightMotion.ProjectEditVC",
        "_TtC12AlightMotion13ProjectEditVC",
    ]

    static func categoryControllerClass() -> AnyClass? {
        firstClass(named: categoryControllerNames)
    }

    static func projectEditorControllerClass() -> AnyClass? {
        firstClass(named: projectEditorControllerNames)
    }

    private static func firstClass(named candidates: [String]) -> AnyClass? {
        for name in candidates {
            if let cls = NSClassFromString(name) { return cls }
        }
        return nil
    }

    static func install() -> Bool {
        let effectPickerInstalled = installHook(
            on: categoryControllerClass(),
            originalSelector: #selector(UIViewController.viewWillAppear(_:)),
            replacementSelector: #selector(UIViewController.aemotion_effectPicker_viewWillAppear(_:))
        )
        let projectEditorInstalled = installHook(
            on: projectEditorControllerClass(),
            originalSelector: #selector(UIViewController.viewDidAppear(_:)),
            replacementSelector: #selector(UIViewController.aemotion_projectEditor_viewDidAppear(_:))
        )
        return effectPickerInstalled || projectEditorInstalled
    }

    private static func installHook(
        on cls: AnyClass?,
        originalSelector: Selector,
        replacementSelector: Selector
    ) -> Bool {
        guard let cls,
              let original = class_getInstanceMethod(cls, originalSelector),
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

nonisolated(unsafe) private var effectPickerProxyKey: UInt8 = 0

extension UIViewController {
    @objc fileprivate func aemotion_effectPicker_viewWillAppear(_ animated: Bool) {
        self.aemotion_effectPicker_viewWillAppear(animated)
        guard String(describing: type(of: self)).contains("EffectPickerMainVC") else { return }
        aemotion_prepareEffectPicker(attempt: 0)
    }

    @objc fileprivate func aemotion_projectEditor_viewDidAppear(_ animated: Bool) {
        self.aemotion_projectEditor_viewDidAppear(animated)
        guard String(describing: type(of: self)).contains("ProjectEditVC") else { return }
        ContextualButtonInjector.install(in: self)
        ContextualButtonInjector.installUtilitiesButtonIfNeeded(in: self)
    }

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
        aemotion_normalizeEffectPickerAppearance()
        aemotion_hideRecommendationStripIfPresent()
        let installed = aemotion_installExtensionsCategoryIfNeeded()
        if installed {
            aemotion_resizeCategoryCollectionIfNeeded()
            aemotion_normalizeEffectPickerAppearance()
            return
        }

        guard attempt < 4 else { return }
        let delay = 0.01 * Double(attempt + 1)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.aemotion_prepareEffectPicker(attempt: attempt + 1)
        }
    }

    @MainActor
    fileprivate func aemotion_normalizeEffectPickerAppearance() {
        view.backgroundColor = AEMotionTheme.background
        navigationController?.view.backgroundColor = AEMotionTheme.background
        aemotion_styleScrollableBackgrounds(in: view)
    }

    @MainActor
    private func aemotion_styleScrollableBackgrounds(in root: UIView) {
        if let collection = root as? UICollectionView, !collection.isHidden {
            AEMotionTheme.apply(to: collection)
            let itemCount = (0..<collection.numberOfSections).reduce(0) {
                $0 + collection.numberOfItems(inSection: $1)
            }
            if itemCount == 0 {
                collection.backgroundView = AEMotionTheme.emptyState(
                    title: "No effects here yet",
                    message: "Choose another category or try searching for an effect.",
                    systemImage: "sparkles"
                )
            } else if collection.backgroundView?.tag == AEMotionTheme.emptyStateTag {
                let backgroundView = UIView()
                backgroundView.tag = AEMotionTheme.solidBackgroundTag
                backgroundView.backgroundColor = AEMotionTheme.background
                collection.backgroundView = backgroundView
            }
        } else if let table = root as? UITableView, !table.isHidden {
            AEMotionTheme.apply(to: table)
        }
        for subview in root.subviews {
            aemotion_styleScrollableBackgrounds(in: subview)
        }
    }

    @MainActor
    private func aemotion_hideRecommendationStripIfPresent() {
        if let recommendation = aemotion_runtimeObject(
            named: "recommendCollectionView"
        ) as? UICollectionView {
            recommendation.isHidden = true
            recommendation.alpha = 0
            recommendation.isUserInteractionEnabled = false
            recommendation.backgroundView = nil
            var frame = recommendation.frame
            frame.size.height = 0
            recommendation.frame = frame
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
        if objc_getAssociatedObject(self, &effectPickerProxyKey) != nil { return true }

        guard let collection = aemotion_categoryCollection(),
              let dataSource = collection.dataSource else {
            return false
        }

        AEMotionTheme.apply(to: collection)
        if dataSource is CategoryCollectionProxy { return true }

        let proxy = CategoryCollectionProxy(
            collectionView: collection,
            originalDataSource: dataSource,
            originalDelegate: collection.delegate,
            presenter: self
        )
        objc_setAssociatedObject(
            self,
            &effectPickerProxyKey,
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
        AEMotionTheme.apply(to: collection)
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
            collection.isScrollEnabled = true
            collection.alwaysBounceVertical = false
            collection.showsVerticalScrollIndicator = true
        }
    }
}
#endif
