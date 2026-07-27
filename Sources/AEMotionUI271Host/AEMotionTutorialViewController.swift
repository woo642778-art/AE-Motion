#if canImport(UIKit)
import UIKit

@MainActor
final class AEMotionTutorialViewController: UIViewController {
    private let scrollView = UIScrollView()
    private let stack = UIStackView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AEMotionProductTheme.canvas
        view.accessibilityIdentifier = "aemotion.tutorial.root"
        configureHierarchy()
    }

    private func configureHierarchy() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 16
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 26, leading: 20, bottom: 130, trailing: 20)

        view.addSubview(scrollView)
        scrollView.addSubview(stack)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
        ])

        stack.addArrangedSubview(makeHero())
        stack.addArrangedSubview(makeFilterRow())

        let lessons: [(String, String, String, String)] = [
            ("START HERE", "5-minute Guided Tour", "Create a project, add a layer, animate two keyframes, preview, and export.", "5 min"),
            ("FOUNDATIONS", "Timeline without friction", "Select, trim, reorder, split, and group layers while keeping the playhead predictable.", "4 min"),
            ("MOTION", "Velocity and graph editing", "Shape motion with handles, easing presets, overshoot, and physically plausible springs.", "7 min"),
            ("COMPOSITING", "Pre-compose correctly", "Create a live nested timeline without flattening the source layers.", "3 min"),
            ("AI TOOLS", "Depth, matte, and cutout", "Use depth-aware isolation, track mattes, and cutout workflows without destructive renders.", "6 min"),
            ("3D", "Build a real 3D scene", "Import GLB assets, light the scene, animate the camera, and hand the result back to the timeline.", "9 min"),
        ]
        for lesson in lessons {
            stack.addArrangedSubview(makeLessonCard(category: lesson.0, title: lesson.1, body: lesson.2, duration: lesson.3))
        }
    }

    private func makeHero() -> UIView {
        let title = UILabel()
        title.text = "Learning Studio"
        title.font = .systemFont(ofSize: 34, weight: .bold)
        title.textColor = AEMotionProductTheme.primaryText

        let subtitle = UILabel()
        subtitle.text = "Short practice paths connected to real editing workflows."
        subtitle.font = .systemFont(ofSize: 17, weight: .medium)
        subtitle.textColor = AEMotionProductTheme.secondaryText
        subtitle.numberOfLines = 0

        let progress = UILabel()
        progress.text = "0 of 6 completed"
        progress.font = .systemFont(ofSize: 15, weight: .semibold)
        progress.textColor = AEMotionProductTheme.accentPurple

        let container = UIStackView(arrangedSubviews: [title, subtitle, progress])
        container.axis = .vertical
        container.spacing = 8
        return container
    }

    private func makeFilterRow() -> UIView {
        let items = ["All", "Composite", "Motion", "3D"]
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 8
        row.distribution = .fillEqually
        for (index, title) in items.enumerated() {
            let button = UIButton(type: .system)
            var configuration = UIButton.Configuration.tinted()
            configuration.title = title
            configuration.baseForegroundColor = index == 0 ? .white : AEMotionProductTheme.secondaryText
            configuration.baseBackgroundColor = index == 0
                ? AEMotionProductTheme.accentPurple
                : AEMotionProductTheme.elevatedSurface
            configuration.cornerStyle = .capsule
            button.configuration = configuration
            button.heightAnchor.constraint(equalToConstant: 42).isActive = true
            row.addArrangedSubview(button)
        }
        return row
    }

    private func makeLessonCard(category: String, title: String, body: String, duration: String) -> UIView {
        let button = UIButton(type: .system)
        button.contentHorizontalAlignment = .fill
        button.backgroundColor = AEMotionProductTheme.elevatedSurface
        button.layer.cornerRadius = 22
        button.layer.cornerCurve = .continuous
        button.layer.borderWidth = 1 / UIScreen.main.scale
        button.layer.borderColor = AEMotionProductTheme.separator.cgColor
        button.accessibilityLabel = "\(title), \(duration)"

        let badge = UILabel()
        badge.text = duration
        badge.font = .systemFont(ofSize: 14, weight: .bold)
        badge.textColor = AEMotionProductTheme.accentPurple
        badge.backgroundColor = AEMotionProductTheme.accentPurple.withAlphaComponent(0.14)
        badge.textAlignment = .center
        badge.layer.cornerRadius = 10
        badge.layer.cornerCurve = .continuous
        badge.clipsToBounds = true
        badge.widthAnchor.constraint(equalToConstant: 62).isActive = true

        let categoryLabel = UILabel()
        categoryLabel.text = category
        categoryLabel.font = .systemFont(ofSize: 13, weight: .bold)
        categoryLabel.textColor = AEMotionProductTheme.secondaryText

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 21, weight: .bold)
        titleLabel.textColor = AEMotionProductTheme.primaryText
        titleLabel.numberOfLines = 0

        let bodyLabel = UILabel()
        bodyLabel.text = body
        bodyLabel.font = .systemFont(ofSize: 15, weight: .medium)
        bodyLabel.textColor = AEMotionProductTheme.secondaryText
        bodyLabel.numberOfLines = 0

        let textStack = UIStackView(arrangedSubviews: [categoryLabel, titleLabel, bodyLabel])
        textStack.axis = .vertical
        textStack.spacing = 5

        let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevron.tintColor = AEMotionProductTheme.tertiaryText
        chevron.setContentHuggingPriority(.required, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [badge, textStack, chevron])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 14
        row.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 18),
            row.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -18),
            row.topAnchor.constraint(equalTo: button.topAnchor, constant: 18),
            row.bottomAnchor.constraint(equalTo: button.bottomAnchor, constant: -18),
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 132),
        ])
        button.addAction(UIAction { [weak self] _ in
            self?.presentLesson(title: title, body: body)
        }, for: .touchUpInside)
        return button
    }

    private func presentLesson(title: String, body: String) {
        let alert = UIAlertController(title: title, message: body, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Mark complete", style: .default))
        alert.addAction(UIAlertAction(title: "Close", style: .cancel))
        present(alert, animated: true)
    }
}
#endif
