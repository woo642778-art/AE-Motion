#if canImport(UIKit)
import UIKit
import ObjectiveC.runtime

final class ExtensionsCategoryCell: UICollectionViewCell {
    static let reuse = "AEMotionExtensionsCategoryCell"
    private let title = UILabel()
    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = UIColor.secondarySystemBackground
        contentView.layer.cornerRadius = 12
        title.text = "Extensions & Scripts"
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.textAlignment = .center
        title.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(title)
        NSLayoutConstraint.activate([title.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8), title.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8), title.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

final class CategoryCollectionProxy: NSObject, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    weak var originalDataSource: UICollectionViewDataSource?
    weak var originalDelegate: UICollectionViewDelegate?
    weak var presenter: UIViewController?
    private weak var collectionView: UICollectionView?
    private var insertionSection = 0
    private var insertionItem = 1

    init(collectionView: UICollectionView, originalDataSource: UICollectionViewDataSource, originalDelegate: UICollectionViewDelegate?, presenter: UIViewController) {
        self.collectionView = collectionView; self.originalDataSource = originalDataSource; self.originalDelegate = originalDelegate; self.presenter = presenter
        super.init()
        collectionView.register(ExtensionsCategoryCell.self, forCellWithReuseIdentifier: ExtensionsCategoryCell.reuse)
        detectMoveTransform(in: collectionView)
    }

    private func detectMoveTransform(in collectionView: UICollectionView) {
        for cell in collectionView.visibleCells {
            let text = labels(in: cell).joined(separator: " ").lowercased()
            if text.contains("move") && text.contains("transform"), let path = collectionView.indexPath(for: cell) {
                insertionSection = path.section; insertionItem = path.item + 1; return
            }
        }
    }

    private func labels(in view: UIView) -> [String] {
        var values: [String] = []
        if let label = view as? UILabel, let text = label.text { values.append(text) }
        for subview in view.subviews { values.append(contentsOf: labels(in: subview)) }
        return values
    }

    func numberOfSections(in collectionView: UICollectionView) -> Int { originalDataSource?.numberOfSections?(in: collectionView) ?? 1 }
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        let count = originalDataSource?.collectionView(collectionView, numberOfItemsInSection: section) ?? 0
        return section == insertionSection ? count + 1 : count
    }
    private func originalPath(_ path: IndexPath) -> IndexPath {
        guard path.section == insertionSection, path.item > insertionItem else { return path }
        return IndexPath(item: path.item - 1, section: path.section)
    }
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if indexPath.section == insertionSection && indexPath.item == insertionItem {
            return collectionView.dequeueReusableCell(withReuseIdentifier: ExtensionsCategoryCell.reuse, for: indexPath)
        }
        guard let source = originalDataSource else { return UICollectionViewCell() }
        return source.collectionView(collectionView, cellForItemAt: originalPath(indexPath))
    }
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if indexPath.section == insertionSection && indexPath.item == insertionItem {
            presenter?.present(UINavigationController(rootViewController: ExtensionsViewController()), animated: true)
        } else {
            originalDelegate?.collectionView?(collectionView, didSelectItemAt: originalPath(indexPath))
        }
    }
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        if let flow = originalDelegate as? UICollectionViewDelegateFlowLayout,
           let size = flow.collectionView?(collectionView, layout: collectionViewLayout, sizeForItemAt: originalPath(indexPath)) { return size }
        return CGSize(width: max(120, collectionView.bounds.width - 32), height: 52)
    }
    override func responds(to selector: Selector!) -> Bool { super.responds(to: selector) || originalDataSource?.responds(to: selector) == true || originalDelegate?.responds(to: selector) == true }
    override func forwardingTarget(for selector: Selector!) -> Any? {
        if originalDelegate?.responds(to: selector) == true { return originalDelegate }
        if originalDataSource?.responds(to: selector) == true { return originalDataSource }
        return super.forwardingTarget(for: selector)
    }
}
#endif
