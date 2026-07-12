#if canImport(UIKit)
import Foundation
import UIKit
import ObjectiveC.runtime

@objc final class RuntimeResolver: NSObject {
    static let categoryControllerNames = [
        "AlightMotion.EffectPickerCategoryVC",
        "_TtC12AlightMotion22EffectPickerCategoryVC",
    ]

    static func categoryControllerClass() -> AnyClass? {
        for name in categoryControllerNames {
            if let cls = NSClassFromString(name) { return cls }
        }
        return nil
    }

    static func install() -> Bool {
        guard let cls = categoryControllerClass(),
              let original = class_getInstanceMethod(cls, #selector(UIViewController.viewDidAppear(_:))),
              let replacement = class_getInstanceMethod(UIViewController.self, #selector(UIViewController.aemotion_viewDidAppear(_:))) else { return false }
        method_exchangeImplementations(original, replacement)
        return true
    }
}

nonisolated(unsafe) private var proxyKey: UInt8 = 0

extension UIViewController {
    @objc fileprivate func aemotion_viewDidAppear(_ animated: Bool) {
        self.aemotion_viewDidAppear(animated)
        guard String(describing: type(of: self)).contains("EffectPickerCategoryVC") else { return }
        guard objc_getAssociatedObject(self, &proxyKey) == nil else { return }
        guard let collection = findCollectionView(in: view), let dataSource = collection.dataSource else { return }
        let proxy = CategoryCollectionProxy(collectionView: collection, originalDataSource: dataSource, originalDelegate: collection.delegate, presenter: self)
        objc_setAssociatedObject(self, &proxyKey, proxy, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        collection.dataSource = proxy
        collection.delegate = proxy
        collection.reloadData()
    }

    private func findCollectionView(in view: UIView) -> UICollectionView? {
        if let collection = view as? UICollectionView { return collection }
        for subview in view.subviews { if let found = findCollectionView(in: subview) { return found } }
        return nil
    }
}
#endif
