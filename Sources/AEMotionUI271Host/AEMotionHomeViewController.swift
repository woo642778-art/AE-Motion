#if canImport(UIKit)
import UIKit
import AEMotionExtensionsCore

@MainActor
enum AEMotionHomeAction: String, Sendable {
    case continueEditing
    case newProject
    case importProject
    case tutorials
    case templates
    case threeDStudio
    case worldStudio
    case precompose
    case tracking
    case matte
    case depthMap
    case textTool
    case speedRemap
    case cutout
    case presetStudio
    case camera
    case assetLibrary
}

struct AEMotionRecentProjectPresentation {
    let title: String
    let metadata: String
    let thumbnail: UIImage?
}

@MainActor
final class AEMotionHomeViewController: UIViewController {
    var actionHandler: ((AEMotionHomeAction) -> Void)?

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let ambientField = AEMotionAmbientFieldView()
    private let recentProjectContainer = UIView()
    private let recentTitle = UILabel()
    private let recentMetadata = UILabel()
    private let recentThumbnail = UIImageView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AEMotionProductTheme.canvas
        view.accessibilityIdentifier = "aemotion.home.surface"
        configureHierarchy()
        configureRecentProject(nil)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        ambientField.setVisibleAndActive(true)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        ambientField.setVisibleAndActive(false)
    }

    func configureRecentProject(_ presentation: AEMotionRecentProjectPresentation?) {
        if let presentation {
            recentTitle.text = presentation.title
            recentMetadata.text = presentation.metadata
            recentThumbnail.image = presentation.thumbnail
            recentThumbnail.isHidden = presentation.thumbnail == nil
            recentProjectContainer.accessibilityLabel = "Continue editing \(presentation.title)"
            recentProjectContainer.accessibilityValue = presentation.metadata
        } else {
            recentTitle.text = "Continue editing"
            recentMetadata.text = "Return to your latest timeline."
            recentThumbnail.image = nil
            recentThumbnail.isHidden = true
            recentProjectContainer.accessibilityLabel = "Continue editing"
            recentProjectContainer.accessibilityValue = "Return to your latest timeline"
        }
    }

    private func configureHierarchy() {
        ambientField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(ambientField)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInset.bottom = AEMotionProductTheme.navigationHeight + 34
        view.addSubview(scrollView)

        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = AEMotionProductTheme.sectionSpacing
        scrollView.addSubview(contentStack)

        contentStack.addArrangedSubview(makeWorkspaceHeader())
        contentStack.addArrangedSubview(makeRecentProjectCard())
        contentStack.addArrangedSubview(makeSectionHeader(title: "Start", subtitle: "Create new work or import an asset."))
        contentStack.addArrangedSubview(makeStartGrid())

        let threeDCard = AEMotionSpotlightCard(
            title: "3D Studio",
            subtitle: "Create, import, animate, and render editable 3D scenes.",
            systemImage: "cube.transparent.fill",
            badge: "3D",
            accessibilityIdentifier: "aemotion.home.3d-studio"
        )
        threeDCard.addAction(UIAction { [weak self] _ in self?.send(.threeDStudio) }, for: .touchUpInside)
        contentStack.addArrangedSubview(threeDCard)

        let worldCard = AEMotionSpotlightCard(
            title: "Real-Time World Studio",
            subtitle: "Edit actor hierarchy, components, cameras, lights, and world assets.",
            systemImage: "globe.americas.fill",
            badge: "LIVE",
            accessibilityIdentifier: "aemotion.home.world-studio"
        )
        worldCard.addAction(UIAction { [weak self] _ in self?.send(.worldStudio) }, for: .touchUpInside)
        contentStack.addArrangedSubview(worldCard)

        contentStack.addArrangedSubview(makeSectionHeader(title: "Quick tools", subtitle: "Open directly in the current project."))
        contentStack.addArrangedSubview(makeQuickTools())

        NSLayoutConstraint.activate([
            ambientField.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            ambientField.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            ambientField.topAnchor.constraint(equalTo: view.topAnchor),
            ambientField.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.42),
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: AEMotionProductTheme.horizontalMargin),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -AEMotionProductTheme.horizontalMargin),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 18),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -28),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -2 * AEMotionProductTheme.horizontalMargin),
        ])
    }

    private func makeWorkspaceHeader() -> UIView {
        let mark = UILabel()
        mark.translatesAutoresizingMaskIntoConstraints = false
        mark.text = "Ae"
        mark.textAlignment = .center
        mark.font = UIFont.systemFont(ofSize: 15, weight: .black)
        mark.textColor = .white
        mark.backgroundColor = AEMotionProductTheme.accentPurple.withAlphaComponent(0.52)
        mark.layer.cornerRadius = 10
        mark.layer.cornerCurve = .continuous
        mark.clipsToBounds = true
        mark.accessibilityLabel = "AE Motion"

        let title = UILabel()
        title.text = "Workspace"
        title.font = AEMotionProductTheme.titleFont()
        title.textColor = AEMotionProductTheme.primaryText
        title.adjustsFontForContentSizeCategory = true
        title.accessibilityIdentifier = "aemotion.home.workspace-title"

        let subtitle = UILabel()
        subtitle.text = "Motion design workspace"
        subtitle.font = AEMotionProductTheme.bodyFont()
        subtitle.textColor = AEMotionProductTheme.secondaryText
        subtitle.adjustsFontForContentSizeCategory = true

        let labels = UIStackView(arrangedSubviews: [title, subtitle])
        labels.axis = .vertical
        labels.spacing = 3

        let version = UILabel()
        version.text = "v\(AEMotionRelease.marketingVersion)"
        version.font = AEMotionProductTheme.captionFont()
        version.textColor = AEMotionProductTheme.accentViolet
        version.setContentCompressionResistancePriority(.required, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [mark, labels, UIView(), version])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 11
        NSLayoutConstraint.activate([
            mark.widthAnchor.constraint(equalToConstant: 42),
            mark.heightAnchor.constraint(equalToConstant: 42),
        ])
        return row
    }

    private func makeRecentProjectCard() -> UIView {
        recentProjectContainer.translatesAutoresizingMaskIntoConstraints = false
        AEMotionProductTheme.configureInteractiveSurface(recentProjectContainer)
        recentProjectContainer.accessibilityIdentifier = "aemotion.home.continue"
        recentProjectContainer.accessibilityTraits = .button
        recentProjectContainer.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(openRecentProject)))

        recentThumbnail.translatesAutoresizingMaskIntoConstraints = false
        recentThumbnail.contentMode = .scaleAspectFill
        recentThumbnail.clipsToBounds = true
        recentThumbnail.layer.cornerRadius = 15
        recentThumbnail.layer.cornerCurve = .continuous
        recentThumbnail.backgroundColor = AEMotionProductTheme.elevatedSurface
        recentThumbnail.isAccessibilityElement = false

        recentTitle.font = AEMotionProductTheme.cardTitleFont()
        recentTitle.textColor = AEMotionProductTheme.primaryText
        recentTitle.numberOfLines = 2
        recentTitle.adjustsFontForContentSizeCategory = true

        recentMetadata.font = AEMotionProductTheme.bodyFont()
        recentMetadata.textColor = AEMotionProductTheme.secondaryText
        recentMetadata.numberOfLines = 2
        recentMetadata.adjustsFontForContentSizeCategory = true

        let eyebrow = UILabel()
        eyebrow.text = "RECENT PROJECT"
        eyebrow.font = UIFont.systemFont(ofSize: 12, weight: .bold)
        eyebrow.textColor = AEMotionProductTheme.accentViolet

        let text = UIStackView(arrangedSubviews: [eyebrow, recentTitle, recentMetadata])
        text.translatesAutoresizingMaskIntoConstraints = false
        text.axis = .vertical
        text.spacing = 4

        let arrow = UIImageView(image: UIImage(systemName: "chevron.right"))
        arrow.translatesAutoresizingMaskIntoConstraints = false
        arrow.tintColor = AEMotionProductTheme.secondaryText
        arrow.contentMode = .scaleAspectFit
        arrow.isAccessibilityElement = false

        recentProjectContainer.addSubview(recentThumbnail)
        recentProjectContainer.addSubview(text)
        recentProjectContainer.addSubview(arrow)
        NSLayoutConstraint.activate([
            recentProjectContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 112),
            recentThumbnail.leadingAnchor.constraint(equalTo: recentProjectContainer.leadingAnchor, constant: 14),
            recentThumbnail.topAnchor.constraint(equalTo: recentProjectContainer.topAnchor, constant: 14),
            recentThumbnail.bottomAnchor.constraint(equalTo: recentProjectContainer.bottomAnchor, constant: -14),
            recentThumbnail.widthAnchor.constraint(equalTo: recentThumbnail.heightAnchor, multiplier: 1.18),
            text.leadingAnchor.constraint(equalTo: recentThumbnail.trailingAnchor, constant: 14),
            text.centerYAnchor.constraint(equalTo: recentProjectContainer.centerYAnchor),
            text.trailingAnchor.constraint(lessThanOrEqualTo: arrow.leadingAnchor, constant: -10),
            arrow.trailingAnchor.constraint(equalTo: recentProjectContainer.trailingAnchor, constant: -17),
            arrow.centerYAnchor.constraint(equalTo: recentProjectContainer.centerYAnchor),
            arrow.widthAnchor.constraint(equalToConstant: 18),
            arrow.heightAnchor.constraint(equalToConstant: 24),
        ])
        return recentProjectContainer
    }

    private func makeStartGrid() -> UIView {
        let actions: [(String, String, AEMotionHomeAction, String)] = [
            ("New project", "plus", .newProject, "aemotion.home.new"),
            ("Import", "square.and.arrow.down", .importProject, "aemotion.home.import"),
            ("Tutorials", "play.rectangle.fill", .tutorials, "aemotion.home.tutorial"),
            ("Templates", "sparkles.rectangle.stack", .templates, "aemotion.home.templates"),
        ]
        let first = UIStackView()
        let second = UIStackView()
        for row in [first, second] {
            row.axis = .horizontal
            row.spacing = 10
            row.distribution = .fillEqually
        }
        for (index, action) in actions.enumerated() {
            let tile = AEMotionActionTile(title: action.0, systemImage: action.1, identifier: action.3)
            tile.addAction(UIAction { [weak self] _ in self?.send(action.2) }, for: .touchUpInside)
            (index < 2 ? first : second).addArrangedSubview(tile)
        }
        let grid = UIStackView(arrangedSubviews: [first, second])
        grid.axis = .vertical
        grid.spacing = 10
        return grid
    }

    private func makeQuickTools() -> UIView {
        let tools: [(String, String, AEMotionHomeAction)] = [
            ("Pre-comp", "square.3.layers.3d", .precompose),
            ("Track", "viewfinder", .tracking),
            ("Matte", "person.crop.rectangle", .matte),
            ("Depth", "square.3.layers.3d.down.right", .depthMap),
            ("Text", "textformat", .textTool),
        ]
        let content = UIStackView()
        content.axis = .horizontal
        content.spacing = 10
        for tool in tools {
            let tile = AEMotionQuickToolTile(title: tool.0, systemImage: tool.1)
            tile.accessibilityIdentifier = "aemotion.home.tool.\(tool.0.lowercased().replacingOccurrences(of: " ", with: "-"))"
            tile.addAction(UIAction { [weak self] _ in self?.send(tool.2) }, for: .touchUpInside)
            content.addArrangedSubview(tile)
        }

        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        scroll.alwaysBounceHorizontal = true
        content.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            content.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
            scroll.heightAnchor.constraint(equalToConstant: 96),
        ])
        return scroll
    }

    private func makeSectionHeader(title: String, subtitle: String) -> UIView {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = AEMotionProductTheme.sectionTitleFont()
        titleLabel.textColor = AEMotionProductTheme.primaryText
        titleLabel.adjustsFontForContentSizeCategory = true

        let subtitleLabel = UILabel()
        subtitleLabel.text = subtitle
        subtitleLabel.font = AEMotionProductTheme.bodyFont()
        subtitleLabel.textColor = AEMotionProductTheme.secondaryText
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        stack.axis = .vertical
        stack.spacing = 3
        return stack
    }

    private func send(_ action: AEMotionHomeAction) {
        AEMotionMotionSystem.selectionHaptic()
        actionHandler?(action)
    }

    @objc private func openRecentProject() { send(.continueEditing) }
}

@MainActor
private final class AEMotionActionTile: UIButton {
    init(title: String, systemImage: String, identifier: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        accessibilityIdentifier = identifier
        var configuration = UIButton.Configuration.filled()
        configuration.title = title
        configuration.image = UIImage(systemName: systemImage)
        configuration.imagePlacement = .top
        configuration.imagePadding = 8
        configuration.baseBackgroundColor = AEMotionProductTheme.surface
        configuration.baseForegroundColor = AEMotionProductTheme.primaryText
        configuration.cornerStyle = .large
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 15, leading: 8, bottom: 15, trailing: 8)
        self.configuration = configuration
        layer.borderColor = AEMotionProductTheme.separator.cgColor
        layer.borderWidth = 1 / UIScreen.main.scale
        heightAnchor.constraint(greaterThanOrEqualToConstant: 92).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

@MainActor
private final class AEMotionQuickToolTile: UIButton {
    init(title: String, systemImage: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        var configuration = UIButton.Configuration.tinted()
        configuration.title = title
        configuration.image = UIImage(systemName: systemImage)
        configuration.imagePlacement = .top
        configuration.imagePadding = 7
        configuration.baseForegroundColor = AEMotionProductTheme.primaryText
        configuration.baseBackgroundColor = AEMotionProductTheme.surface
        configuration.cornerStyle = .large
        self.configuration = configuration
        layer.borderColor = AEMotionProductTheme.separator.cgColor
        layer.borderWidth = 1 / UIScreen.main.scale
        widthAnchor.constraint(equalToConstant: 104).isActive = true
        heightAnchor.constraint(equalToConstant: 92).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
#endif
