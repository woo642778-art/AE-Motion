#if canImport(UIKit)
import UIKit

@MainActor
final class AEMotionCreateTrayController: UIViewController {
    var onDismiss: (() -> Void)?
    var onAction: ((AEMotionHomeAction) -> Void)?

    private let backdropControl = UIControl()
    private let cardView = UIView()
    private let stackView = UIStackView()
    private var isPresentedState = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.accessibilityIdentifier = "aemotion.create-tray.root"
        configureHierarchy()
        setPresented(false, animated: false)
    }

    func setPresented(_ presented: Bool, animated: Bool) {
        loadViewIfNeeded()
        isPresentedState = presented
        view.isHidden = !presented
        view.isUserInteractionEnabled = presented
        backdropControl.isUserInteractionEnabled = presented
        cardView.isUserInteractionEnabled = presented

        let changes = {
            self.backdropControl.alpha = presented ? 1 : 0
            self.cardView.alpha = presented ? 1 : 0
            self.cardView.transform = presented
                ? .identity
                : CGAffineTransform(translationX: 0, y: 18).scaledBy(x: 0.97, y: 0.97)
        }

        guard animated, !UIAccessibility.isReduceMotionEnabled else {
            changes()
            return
        }

        if presented {
            view.isHidden = false
            UIView.animate(
                withDuration: 0.30,
                delay: 0,
                usingSpringWithDamping: 0.86,
                initialSpringVelocity: 0.35,
                options: [.allowUserInteraction, .beginFromCurrentState],
                animations: changes
            )
        } else {
            UIView.animate(
                withDuration: 0.20,
                delay: 0,
                options: [.curveEaseIn, .beginFromCurrentState],
                animations: changes
            ) { _ in
                guard !self.isPresentedState else { return }
                self.view.isHidden = true
            }
        }
    }

    private func configureHierarchy() {
        backdropControl.translatesAutoresizingMaskIntoConstraints = false
        backdropControl.backgroundColor = UIColor.black.withAlphaComponent(0.42)
        backdropControl.accessibilityIdentifier = "aemotion.create-tray.dismiss-region"
        backdropControl.addAction(UIAction { [weak self] _ in
            self?.onDismiss?()
        }, for: .touchUpInside)
        view.addSubview(backdropControl)

        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.backgroundColor = AEMotionProductTheme.elevatedSurface
        cardView.layer.cornerRadius = 24
        cardView.layer.cornerCurve = .continuous
        cardView.layer.borderWidth = 1 / UIScreen.main.scale
        cardView.layer.borderColor = AEMotionProductTheme.separator.cgColor
        cardView.layer.shadowColor = UIColor.black.cgColor
        cardView.layer.shadowOpacity = 0.34
        cardView.layer.shadowRadius = 24
        cardView.layer.shadowOffset = CGSize(width: 0, height: 12)
        cardView.accessibilityIdentifier = "aemotion.create-tray.card"
        view.addSubview(cardView)

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.alignment = .fill
        stackView.distribution = .fillEqually
        stackView.spacing = 8
        cardView.addSubview(stackView)

        let actions: [(String, String, AEMotionHomeAction)] = [
            ("New Project", "plus.square.fill", .newProject),
            ("Import", "square.and.arrow.down.fill", .importProject),
            ("Camera", "camera.fill", .camera),
            ("Asset Library", "photo.stack.fill", .assetLibrary),
        ]
        for item in actions {
            let button = makeActionButton(title: item.0, symbol: item.1)
            button.accessibilityIdentifier = "aemotion.create-tray.\(item.2.rawValue)"
            button.addAction(UIAction { [weak self] _ in
                self?.onAction?(item.2)
            }, for: .touchUpInside)
            stackView.addArrangedSubview(button)
        }

        NSLayoutConstraint.activate([
            backdropControl.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backdropControl.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backdropControl.topAnchor.constraint(equalTo: view.topAnchor),
            backdropControl.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            cardView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            cardView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            cardView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -92),
            cardView.heightAnchor.constraint(greaterThanOrEqualToConstant: 112),

            stackView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 10),
            stackView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -10),
            stackView.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 10),
            stackView.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -10),
        ])
    }

    private func makeActionButton(title: String, symbol: String) -> UIButton {
        let button = UIButton(type: .system)
        var configuration = UIButton.Configuration.tinted()
        configuration.title = title
        configuration.image = UIImage(systemName: symbol)
        configuration.imagePlacement = .top
        configuration.imagePadding = 8
        configuration.baseForegroundColor = .white
        configuration.baseBackgroundColor = AEMotionProductTheme.accentPurple.withAlphaComponent(0.14)
        configuration.cornerStyle = .large
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 4, bottom: 12, trailing: 4)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 13, weight: .semibold)
            return outgoing
        }
        button.configuration = configuration
        button.titleLabel?.numberOfLines = 2
        button.titleLabel?.textAlignment = .center
        return button
    }
}
#endif
