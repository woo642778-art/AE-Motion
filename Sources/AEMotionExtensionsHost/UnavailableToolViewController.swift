#if canImport(UIKit)
import UIKit

@MainActor
final class UnavailableToolViewController: UIViewController {
    private let toolTitle: String
    private let reason: String

    init(toolTitle: String, reason: String) {
        self.toolTitle = toolTitle
        self.reason = reason
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = toolTitle
        AEMotionTheme.apply(to: self)

        let image = UIImageView(image: UIImage(systemName: "exclamationmark.triangle"))
        image.tintColor = .secondaryLabel
        image.contentMode = .scaleAspectFit
        image.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.text = "Tool unavailable"
        titleLabel.font = .preferredFont(forTextStyle: .title2)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let reasonLabel = UILabel()
        reasonLabel.text = reason
        reasonLabel.font = .preferredFont(forTextStyle: .body)
        reasonLabel.textColor = .secondaryLabel
        reasonLabel.textAlignment = .center
        reasonLabel.numberOfLines = 0
        reasonLabel.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [image, titleLabel, reasonLabel])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            image.heightAnchor.constraint(equalToConstant: 52),
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }
}
#endif
