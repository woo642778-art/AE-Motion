#if canImport(UIKit)
import UIKit
import ObjectiveC.runtime

@MainActor
final class ExtensionsCategoryCell: UICollectionViewCell {
    static let reuse = "AEMotionExtensionsCategoryCell"
    private let icon = UIImageView(image: UIImage(systemName: "wand.and.stars"))
    private let title = UILabel()
    private let subtitle = UILabel()

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.12) {
                self.contentView.alpha = self.isHighlighted ? 0.68 : 1
            }
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = AEMotionTheme.surface
        contentView.layer.cornerRadius = AEMotionTheme.cornerRadius
        contentView.layer.cornerCurve = .continuous
        contentView.layer.borderWidth = 1 / UIScreen.main.scale
        contentView.layer.borderColor = AEMotionTheme.separator.cgColor

        icon.tintColor = AEMotionTheme.accent
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false

        title.text = "Extensions & Scripts"
        title.font = .preferredFont(forTextStyle: .headline)
        title.textColor = AEMotionTheme.primaryText
        title.adjustsFontForContentSizeCategory = true

        subtitle.text = "AE Motion tools, presets and diagnostics"
        subtitle.font = .preferredFont(forTextStyle: .caption1)
        subtitle.textColor = AEMotionTheme.secondaryText
        subtitle.adjustsFontForContentSizeCategory = true
        subtitle.numberOfLines = 1

        let labels = UIStackView(arrangedSubviews: [title, subtitle])
        labels.axis = .vertical
        labels.spacing = 2
        labels.translatesAutoresizingMaskIntoConstraints = false

        let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevron.tintColor = .tertiaryLabel
        chevron.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(icon)
        contentView.addSubview(labels)
        contentView.addSubview(chevron)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            icon.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 24),
            icon.heightAnchor.constraint(equalToConstant: 24),

            labels.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12),
            labels.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            labels.trailingAnchor.constraint(lessThanOrEqualTo: chevron.leadingAnchor, constant: -10),

            chevron.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
            chevron.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 8),
        ])
        accessibilityTraits = .button
        accessibilityLabel = "Extensions & Scripts"
        accessibilityHint = "Opens AE Motion tools and presets"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@MainActor
final class CategoryCollectionProxy: NSObject, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    weak var originalDataSource: UICollectionViewDataSource?
    weak var originalDelegate: UICollectionViewDelegate?
    weak var presenter: UIViewController?
    private weak var collectionView: UICollectionView?
    private var insertionSection = 0
    private var insertionItem = 1

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
        AEMotionTheme.apply(to: collectionView)
        if collectionView.backgroundView == nil {
            let backgroundView = UIView()
            backgroundView.tag = AEMotionTheme.solidBackgroundTag
            backgroundView.backgroundColor = AEMotionTheme.background
            collectionView.backgroundView = backgroundView
        }
        collectionView.register(
            ExtensionsCategoryCell.self,
            forCellWithReuseIdentifier: ExtensionsCategoryCell.reuse
        )
        detectMoveTransform(in: collectionView)
    }

    private func detectMoveTransform(in collectionView: UICollectionView) {
        for cell in collectionView.visibleCells {
            let text = labels(in: cell).joined(separator: " ").lowercased()
            if text.contains("move") && text.contains("transform"),
               let path = collectionView.indexPath(for: cell) {
                insertionSection = path.section
                insertionItem = path.item + 1
                return
            }
        }
    }

    private func labels(in view: UIView) -> [String] {
        var values: [String] = []
        if let label = view as? UILabel, let text = label.text { values.append(text) }
        for subview in view.subviews { values.append(contentsOf: labels(in: subview)) }
        return values
    }

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        originalDataSource?.numberOfSections?(in: collectionView) ?? 1
    }

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
            return collectionView.dequeueReusableCell(
                withReuseIdentifier: ExtensionsCategoryCell.reuse,
                for: indexPath
            )
        }
        guard let source = originalDataSource else { return UICollectionViewCell() }
        return source.collectionView(collectionView, cellForItemAt: originalPath(indexPath))
    }


    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if indexPath.section == insertionSection && indexPath.item == insertionItem {
            guard let presenter else { return }
            let navigation = UINavigationController(rootViewController: ExtensionsViewController(style: .insetGrouped))
            navigation.modalPresentationStyle = .pageSheet
            presenter.present(navigation, animated: true)
        } else {
            originalDelegate?.collectionView?(collectionView, didSelectItemAt: originalPath(indexPath))
        }
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        if let flow = originalDelegate as? UICollectionViewDelegateFlowLayout,
           let size = flow.collectionView?(
               collectionView,
               layout: collectionViewLayout,
               sizeForItemAt: originalPath(indexPath)
           ) {
            return size
        }
        return CGSize(width: max(120, collectionView.bounds.width - 32), height: 64)
    }

    override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector)
            || originalDataSource?.responds(to: selector) == true
            || originalDelegate?.responds(to: selector) == true
    }

    override func forwardingTarget(for selector: Selector!) -> Any? {
        if originalDelegate?.responds(to: selector) == true { return originalDelegate }
        if originalDataSource?.responds(to: selector) == true { return originalDataSource }
        return super.forwardingTarget(for: selector)
    }
}
#endif
