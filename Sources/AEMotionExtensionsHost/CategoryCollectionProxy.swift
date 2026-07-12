#if canImport(UIKit)
import UIKit
import ObjectiveC.runtime

final class ExtensionsCategoryCell: UICollectionViewCell {
    static let reuse = "AEMotionExtensionsCategoryCell"

    private let iconView = UIImageView(image: UIImage(systemName: "puzzlepiece.extension.fill"))
    private let titleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)

        contentView.backgroundColor = UIColor.secondarySystemBackground
        contentView.layer.cornerRadius = 12
        contentView.layer.masksToBounds = true

        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = .label
        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.text = "Extensions & Scripts"
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 2
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.75
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(iconView)
        contentView.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            iconView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            iconView.widthAnchor.constraint(equalToConstant: 30),
            iconView.heightAnchor.constraint(equalToConstant: 30),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 6),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -6),
            titleLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 6),
            titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -6),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class CategoryCollectionProxy: NSObject, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    nonisolated(unsafe) weak var originalDataSource: UICollectionViewDataSource?
    nonisolated(unsafe) weak var originalDelegate: UICollectionViewDelegate?
    weak var presenter: UIViewController?

    private weak var collectionView: UICollectionView?
    private var insertionSection = 0
    // Alight Motion 6.2.42 category order:
    // Color & Light, Drawing & Edge, Blur, Warp, Procedural, 3D,
    // Move & Transform, Repeat, Matte/Mask, Opacity, Text.
    private var insertionItem = 7

    init(
        collectionView: UICollectionView,
        originalDataSource: UICollectionViewDataSource,
        originalDelegate: UICollectionViewDelegate?,
        presenter: UIViewController
    ) {
        self.collectionView = collectionView
        self.originalDataSource = originalDataSource
        self.originalDelegate = originalDelegate
        self.presenter = presenter
        super.init()

        collectionView.register(
            ExtensionsCategoryCell.self,
            forCellWithReuseIdentifier: ExtensionsCategoryCell.reuse
        )

        // The original category collection does not need prefetching. Disabling it
        // prevents shifted index paths from reaching a private prefetch handler.
        collectionView.prefetchDataSource = nil
        detectMoveTransform(in: collectionView)
    }

    private func detectMoveTransform(in collectionView: UICollectionView) {
        let originalCount = originalDataSource?.collectionView(
            collectionView,
            numberOfItemsInSection: insertionSection
        ) ?? 0
        insertionItem = min(7, originalCount)

        collectionView.layoutIfNeeded()
        for cell in collectionView.visibleCells {
            let text = labels(in: cell).joined(separator: " ").lowercased()
            if text.contains("move") && text.contains("transform"),
               let path = collectionView.indexPath(for: cell) {
                insertionSection = path.section
                insertionItem = min(path.item + 1, originalCount)
                return
            }
        }
    }

    private func labels(in view: UIView) -> [String] {
        var values: [String] = []
        if let label = view as? UILabel, let text = label.text {
            values.append(text)
        }
        for subview in view.subviews {
            values.append(contentsOf: labels(in: subview))
        }
        return values
    }

    private func isExtensionPath(_ path: IndexPath) -> Bool {
        path.section == insertionSection && path.item == insertionItem
    }

    private func originalPath(_ path: IndexPath) -> IndexPath {
        guard path.section == insertionSection, path.item > insertionItem else {
            return path
        }
        return IndexPath(item: path.item - 1, section: path.section)
    }

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        originalDataSource?.numberOfSections?(in: collectionView) ?? 1
    }

    func collectionView(
        _ collectionView: UICollectionView,
        numberOfItemsInSection section: Int
    ) -> Int {
        let count = originalDataSource?.collectionView(
            collectionView,
            numberOfItemsInSection: section
        ) ?? 0
        return section == insertionSection ? count + 1 : count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        if isExtensionPath(indexPath) {
            return collectionView.dequeueReusableCell(
                withReuseIdentifier: ExtensionsCategoryCell.reuse,
                for: indexPath
            )
        }

        guard let source = originalDataSource else {
            return UICollectionViewCell()
        }
        return source.collectionView(
            collectionView,
            cellForItemAt: originalPath(indexPath)
        )
    }

    func collectionView(
        _ collectionView: UICollectionView,
        didSelectItemAt indexPath: IndexPath
    ) {
        if isExtensionPath(indexPath) {
            collectionView.deselectItem(at: indexPath, animated: true)
            presenter?.present(
                UINavigationController(rootViewController: ExtensionsViewController()),
                animated: true
            )
            return
        }

        originalDelegate?.collectionView?(
            collectionView,
            didSelectItemAt: originalPath(indexPath)
        )
    }

    func collectionView(
        _ collectionView: UICollectionView,
        shouldSelectItemAt indexPath: IndexPath
    ) -> Bool {
        if isExtensionPath(indexPath) { return true }
        return originalDelegate?.collectionView?(
            collectionView,
            shouldSelectItemAt: originalPath(indexPath)
        ) ?? true
    }


    func collectionView(
        _ collectionView: UICollectionView,
        shouldDeselectItemAt indexPath: IndexPath
    ) -> Bool {
        if isExtensionPath(indexPath) { return true }
        return originalDelegate?.collectionView?(
            collectionView,
            shouldDeselectItemAt: originalPath(indexPath)
        ) ?? true
    }

    func collectionView(
        _ collectionView: UICollectionView,
        didDeselectItemAt indexPath: IndexPath
    ) {
        guard !isExtensionPath(indexPath) else { return }
        originalDelegate?.collectionView?(
            collectionView,
            didDeselectItemAt: originalPath(indexPath)
        )
    }

    func collectionView(
        _ collectionView: UICollectionView,
        shouldHighlightItemAt indexPath: IndexPath
    ) -> Bool {
        if isExtensionPath(indexPath) { return true }
        return originalDelegate?.collectionView?(
            collectionView,
            shouldHighlightItemAt: originalPath(indexPath)
        ) ?? true
    }

    func collectionView(
        _ collectionView: UICollectionView,
        didHighlightItemAt indexPath: IndexPath
    ) {
        guard !isExtensionPath(indexPath) else { return }
        originalDelegate?.collectionView?(
            collectionView,
            didHighlightItemAt: originalPath(indexPath)
        )
    }

    func collectionView(
        _ collectionView: UICollectionView,
        didUnhighlightItemAt indexPath: IndexPath
    ) {
        guard !isExtensionPath(indexPath) else { return }
        originalDelegate?.collectionView?(
            collectionView,
            didUnhighlightItemAt: originalPath(indexPath)
        )
    }

    func collectionView(
        _ collectionView: UICollectionView,
        willDisplay cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        // Never send the synthetic Extensions cell to Alight Motion's private
        // delegate. Every stock item after the insertion point is translated
        // back by one before the original delegate sees it.
        guard !isExtensionPath(indexPath) else { return }
        originalDelegate?.collectionView?(
            collectionView,
            willDisplay: cell,
            forItemAt: originalPath(indexPath)
        )
    }

    func collectionView(
        _ collectionView: UICollectionView,
        didEndDisplaying cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        guard !isExtensionPath(indexPath) else { return }
        originalDelegate?.collectionView?(
            collectionView,
            didEndDisplaying: cell,
            forItemAt: originalPath(indexPath)
        )
    }

    func collectionView(
        _ collectionView: UICollectionView,
        canFocusItemAt indexPath: IndexPath
    ) -> Bool {
        if isExtensionPath(indexPath) { return true }
        return originalDelegate?.collectionView?(
            collectionView,
            canFocusItemAt: originalPath(indexPath)
        ) ?? true
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        if isExtensionPath(indexPath) {
            let reference = IndexPath(item: max(0, insertionItem - 1), section: insertionSection)
            if let flow = originalDelegate as? UICollectionViewDelegateFlowLayout,
               let size = flow.collectionView?(
                   collectionView,
                   layout: collectionViewLayout,
                   sizeForItemAt: reference
               ) {
                return size
            }
        } else if let flow = originalDelegate as? UICollectionViewDelegateFlowLayout,
                  let size = flow.collectionView?(
                      collectionView,
                      layout: collectionViewLayout,
                      sizeForItemAt: originalPath(indexPath)
                  ) {
            return size
        }

        return CGSize(width: 120, height: 110)
    }

    nonisolated private func isUnsafeForwardedItemSelector(_ selector: Selector) -> Bool {
        let name = NSStringFromSelector(selector).lowercased()
        // Unknown optional/private callbacks carrying an item index path cannot
        // be forwarded verbatim after inserting a synthetic cell. Returning
        // false from responds(to:) makes UIKit skip those optional callbacks
        // instead of sending an out-of-range shifted index path to the app.
        return name.contains("indexpath") ||
            name.contains("foritemat") ||
            name.contains("itematindex")
    }

    override func responds(to selector: Selector!) -> Bool {
        if super.responds(to: selector) { return true }
        guard let selector else { return false }
        if isUnsafeForwardedItemSelector(selector) { return false }
        if originalDataSource?.responds(to: selector) == true { return true }
        return originalDelegate?.responds(to: selector) == true
    }

    override func forwardingTarget(for selector: Selector!) -> Any? {
        guard let selector else { return super.forwardingTarget(for: selector) }
        if isUnsafeForwardedItemSelector(selector) {
            return super.forwardingTarget(for: selector)
        }
        if originalDelegate?.responds(to: selector) == true {
            return originalDelegate
        }
        if originalDataSource?.responds(to: selector) == true {
            return originalDataSource
        }
        return super.forwardingTarget(for: selector)
    }
}
#endif
