#if canImport(UIKit)
import UIKit

@MainActor
enum AEMotionTheme {
    static var background: UIColor { .systemGroupedBackground }
    static var surface: UIColor { .secondarySystemGroupedBackground }
    static var elevatedSurface: UIColor { .tertiarySystemGroupedBackground }
    static var primaryText: UIColor { .label }
    static var secondaryText: UIColor { .secondaryLabel }
    static var separator: UIColor { .separator }
    static var accent: UIColor { .systemBlue }
    static var cornerRadius: CGFloat { 11 }
    static var horizontalMargin: CGFloat { 16 }
    static var sectionSpacing: CGFloat { 12 }
    static let emptyStateTag = 0xAE0202
    static let solidBackgroundTag = 0xAE0203

    static func apply(to controller: UIViewController) {
        controller.view.backgroundColor = background
        controller.navigationItem.backButtonDisplayMode = .minimal
        controller.navigationController?.navigationBar.tintColor = accent
    }

    static func apply(to tableView: UITableView) {
        tableView.backgroundColor = background
        tableView.separatorColor = separator
        tableView.keyboardDismissMode = .interactive
        tableView.sectionHeaderTopPadding = 10
        tableView.backgroundView = tableView.backgroundView ?? UIView()
        tableView.backgroundView?.backgroundColor = background
    }

    static func apply(to scrollView: UIScrollView) {
        scrollView.backgroundColor = background
        scrollView.indicatorStyle = .default
    }

    static func apply(to collectionView: UICollectionView) {
        collectionView.backgroundColor = background
        if collectionView.backgroundView == nil {
            let backgroundView = UIView()
            backgroundView.tag = solidBackgroundTag
            backgroundView.backgroundColor = background
            collectionView.backgroundView = backgroundView
        } else {
            collectionView.backgroundView?.backgroundColor = background
        }
    }

    static func style(field: UITextField) {
        field.borderStyle = .none
        field.backgroundColor = surface
        field.textColor = primaryText
        field.tintColor = accent
        field.layer.cornerRadius = 9
        field.layer.masksToBounds = true
        field.setLeftPadding(12)
        field.setRightPadding(12)
        field.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
    }

    static func style(primary button: UIButton) {
        var configuration = UIButton.Configuration.filled()
        configuration.baseBackgroundColor = accent
        configuration.baseForegroundColor = .white
        configuration.cornerStyle = .medium
        configuration.buttonSize = .medium
        button.configuration = configuration
        button.titleLabel?.adjustsFontForContentSizeCategory = true
    }

    static func style(secondary button: UIButton) {
        var configuration = UIButton.Configuration.tinted()
        configuration.baseBackgroundColor = accent
        configuration.baseForegroundColor = accent
        configuration.cornerStyle = .medium
        configuration.buttonSize = .medium
        button.configuration = configuration
        button.titleLabel?.adjustsFontForContentSizeCategory = true
    }

    static func emptyState(
        title: String,
        message: String,
        systemImage: String,
        actionTitle: String? = nil,
        action: UIAction? = nil
    ) -> UIView {
        let image = UIImageView(image: UIImage(systemName: systemImage))
        image.tintColor = secondaryText
        image.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 28, weight: .regular)
        image.contentMode = .scaleAspectFit
        image.heightAnchor.constraint(equalToConstant: 36).isActive = true

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textColor = primaryText
        titleLabel.textAlignment = .center
        titleLabel.adjustsFontForContentSizeCategory = true

        let messageLabel = UILabel()
        messageLabel.text = message
        messageLabel.font = .preferredFont(forTextStyle: .subheadline)
        messageLabel.textColor = secondaryText
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.adjustsFontForContentSizeCategory = true

        var views: [UIView] = [image, titleLabel, messageLabel]
        if let actionTitle, let action {
            let button = UIButton(type: .system, primaryAction: action)
            style(secondary: button)
            var configuration = button.configuration
            configuration?.title = actionTitle
            button.configuration = configuration
            views.append(button)
        }

        let stack = UIStackView(arrangedSubviews: views)
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 9
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = UIView()
        container.tag = emptyStateTag
        container.backgroundColor = background
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -28),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 360),
        ])
        return container
    }


    static func styleControls(in root: UIView) {
        switch root {
        case let textView as UITextView:
            textView.backgroundColor = surface
            textView.textColor = primaryText
            textView.tintColor = accent
            textView.layer.cornerRadius = cornerRadius
            textView.layer.cornerCurve = .continuous
            textView.textContainerInset = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        case let slider as UISlider:
            slider.minimumTrackTintColor = accent
        case let toggle as UISwitch:
            toggle.onTintColor = accent
        case let segmented as UISegmentedControl:
            segmented.selectedSegmentTintColor = surface
        default:
            break
        }
        for subview in root.subviews {
            styleControls(in: subview)
        }
    }

    static func configure(cell: UITableViewCell, iconName: String?) {
        cell.backgroundColor = surface
        cell.tintColor = accent
        cell.selectionStyle = .default
        if let iconName {
            cell.imageView?.image = UIImage(systemName: iconName)
        }
    }
}

private extension UITextField {
    func setLeftPadding(_ width: CGFloat) {
        let spacer = UIView(frame: CGRect(x: 0, y: 0, width: width, height: 1))
        leftView = spacer
        leftViewMode = .always
    }

    func setRightPadding(_ width: CGFloat) {
        let spacer = UIView(frame: CGRect(x: 0, y: 0, width: width, height: 1))
        rightView = spacer
        rightViewMode = .always
    }
}
#endif
