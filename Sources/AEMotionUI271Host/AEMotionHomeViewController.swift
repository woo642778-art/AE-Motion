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
    case speedRemap
    case cutout
    case depthMap
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
    private var recentProject: AEMotionRecentProjectPresentation?

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
        recentProject = presentation
        if let presentation {
            recentTitle.text = presentation.title
            recentMetadata.text = presentation.metadata
            recentThumbnail.image = presentation.thumbnail
            recentThumbnail.isHidden = presentation.thumbnail == nil
            recentProjectContainer.accessibilityLabel = "Continue editing \(presentation.title)"
            recentProjectContainer.accessibilityValue = presentation.metadata
        } else {
            recentTitle.text = "Continue editing"
            recentMetadata.text = "Open your most recent Alight Motion project"
            recentThumbnail.image = nil
            recentThumbnail.isHidden = true
            recentProjectContainer.accessibilityLabel = "Continue editing"
            recentProjectContainer.accessibilityValue = "Open your most recent project"
        }
    }

    private func configureHierarchy() {
        ambientField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(ambientField)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInset.bottom = AEMotionProductTheme.navigationHeight + 30
        view.addSubview(scrollView)

        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = AEMotionProductTheme.sectionSpacing
        scrollView.addSubview(contentStack)

        contentStack.addArrangedSubview(makeProductHeader())
        contentStack.addArrangedSubview(makeWorkspaceHeader())
        contentStack.addArrangedSubview(makeRecentProjectCard())
        contentStack.addArrangedSubview(makeSectionTitle("Start"))
        contentStack.addArrangedSubview(makeStartGrid())

        let threeDCard = AEMotionSpotlightCard(
            title: "3D Studio",
            subtitle: "Model, animate, light, and render in a focused mobile workspace.",
            systemImage: "cube.transparent.fill",
            badge: "PRO",
            accessibilityIdentifier: "aemotion.home.3d-studio"
        )
        threeDCard.addAction(UIAction { [weak self] _ in self?.send(.threeDStudio) }, for: .touchUpInside)
        contentStack.addArrangedSubview(threeDCard)

        let worldCard = AEMotionSpotlightCard(
            title: "Real-Time World Studio",
            subtitle: "Build actor, component, camera, and environment driven worlds.",
            systemImage: "globe.americas.fill",
            badge: "LIVE",
            accessibilityIdentifier: "aemotion.home.world-studio"
        )
        worldCard.addAction(UIAction { [weak self] _ in self?.send(.worldStudio) }, for: .touchUpInside)
        contentStack.addArrangedSubview(worldCard)

        contentStack.addArrangedSubview(makeSectionTitle("Quick tools"))
        contentStack.addArrangedSubview(makeQuickTools())

        NSLayoutConstraint.activate([
            ambientField.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            ambientField.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            ambientField.topAnchor.constraint(equalTo: view.topAnchor),
            ambientField.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.48),
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: AEMotionProductTheme.horizontalMargin),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -AEMotionProductTheme.horizontalMargin),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 18),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -2 * AEMotionProductTheme.horizontalMargin),
        ])
    }

    private func makeProductHeader() -> UIView {
        let mark = UILabel()
        mark.text = "AE"
        mark.font = UIFont.systemFont(ofSize: 14, weight: .black)
        mark.textColor = .white
        mark.textAlignment = .center
        mark.backgroundColor = AEMotionProductTheme.accentPurple
        mark.layer.cornerRadius = 10
        mark.layer.cornerCurve = .continuous
        mark.clipsToBounds = true
        mark.translatesAutoresizingMaskIntoConstraints = false
        mark.accessibilityLabel = "AE Motion"

        let name = UILabel()
        name.text = "AE Motion"
        name.font = UIFont.systemFont(ofSize: 17, weight: .bold)
        name.textColor = AEMotionProductTheme.primaryText

        let version = UILabel()
        version.text = "v\(AEMotionRelease.marketingVersion)"
        version.font = AEMotionProductTheme.captionFont()
        version.textColor = AEMotionProductTheme.secondaryText

        let text = UIStackView(arrangedSubviews: [name, version])
        text.axis = .vertical
        text.spacing = 1

        let spacer = UIView()
        let release = UIButton(type: .system)
        var configuration = UIButton.Configuration.tinted()
        configuration.image = UIImage(systemName: "sparkles")
        configuration.title = "What’s new"
        configuration.imagePadding = 5
        configuration.cornerStyle = .capsule
        configuration.baseForegroundColor = AEMotionProductTheme.accentViolet
        configuration.baseBackgroundColor = AEMotionProductTheme.accentPurple.withAlphaComponent(0.16)
        release.configuration = configuration
        release.accessibilityIdentifier = "aemotion.home.release-history"

        let row = UIStackView(arrangedSubviews: [mark, text, spacer, release])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 10
        NSLayoutConstraint.activate([
            mark.widthAnchor.constraint(equalToConstant: 38),
            mark.heightAnchor.constraint(equalToConstant: 38),
            release.heightAnchor.constraint(greaterThanOrEqualToConstant: AEMotionProductTheme.minimumTouchTarget),
        ])
        return row
    }

    private func makeWorkspaceHeader() -> UIView {
        let title = UILabel()
        title.text = "Workspace"
        title.font = AEMotionProductTheme.titleFont()
        title.textColor = AEMotionProductTheme.primaryText
        title.adjustsFontForContentSizeCategory = true
        title.accessibilityIdentifier = "aemotion.home.workspace-title"

        let subtitle = UILabel()
        subtitle.text = "Create faster. Push motion further."
        subtitle.font = AEMotionProductTheme.bodyFont()
        subtitle.textColor = AEMotionProductTheme.secondaryText
        subtitle.adjustsFontForContentSizeCategory = true

        let stack = UIStackView(arrangedSubviews: [title, subtitle])
        stack.axis = .vertical
        stack.spacing = 4
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 6, leading: 0, bottom: 2, trailing: 0)
        return stack
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
        recentThumbnail.layer.cornerRadius = 16
        recentThumbnail.layer.cornerCurve = .continuous
        recentThumbnail.backgroundColor = AEMotionProductTheme.elevatedSurface
        recentThumbnail.isAccessibilityElement = false

        recentTitle.translatesAutoresizingMaskIntoConstraints = false
        recentTitle.font = AEMotionProductTheme.cardTitleFont()
        recentTitle.textColor = AEMotionProductTheme.primaryText
        recentTitle.numberOfLines = 2
        recentTitle.adjustsFontForContentSizeCategory = true

        recentMetadata.translatesAutoresizingMaskIntoConstraints = false
        recentMetadata.font = AEMotionProductTheme.bodyFont()
        recentMetadata.textColor = AEMotionProductTheme.secondaryText
        recentMetadata.numberOfLines = 2
        recentMetadata.adjustsFontForContentSizeCategory = true

        let text = UIStackView(arrangedSubviews: [recentTitle, recentMetadata])
        text.translatesAutoresizingMaskIntoConstraints = false
        text.axis = .vertical
        text.spacing = 5

        let arrow = UIImageView(image: UIImage(systemName: "play.fill"))
        arrow.translatesAutoresizingMaskIntoConstraints = false
        arrow.tintColor = .white
        arrow.backgroundColor = AEMotionProductTheme.accentPurple
        arrow.contentMode = .center
        arrow.layer.cornerRadius = 20
        arrow.layer.cornerCurve = .continuous
        arrow.isAccessibilityElement = false

        recentProjectContainer.addSubview(recentThumbnail)
        recentProjectContainer.addSubview(text)
        recentProjectContainer.addSubview(arrow)
        NSLayoutConstraint.activate([
            recentProjectContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 112),
            recentThumbnail.leadingAnchor.constraint(equalTo: recentProjectContainer.leadingAnchor, constant: 14),
            recentThumbnail.topAnchor.constraint(equalTo: recentProjectContainer.topAnchor, constant: 14),
            recentThumbnail.bottomAnchor.constraint(equalTo: recentProjectContainer.bottomAnchor, constant: -14),
            recentThumbnail.widthAnchor.constraint(equalTo: recentThumbnail.heightAnchor, multiplier: 1.32),
            text.leadingAnchor.constraint(equalTo: recentThumbnail.trailingAnchor, constant: 14),
            text.centerYAnchor.constraint(equalTo: recentProjectContainer.centerYAnchor),
            text.trailingAnchor.constraint(lessThanOrEqualTo: arrow.leadingAnchor, constant: -12),
            arrow.trailingAnchor.constraint(equalTo: recentProjectContainer.trailingAnchor, constant: -16),
            arrow.centerYAnchor.constraint(equalTo: recentProjectContainer.centerYAnchor),
            arrow.widthAnchor.constraint(equalToConstant: 40),
            arrow.heightAnchor.constraint(equalToConstant: 40),
        ])
        return recentProjectContainer
    }

    private func makeStartGrid() -> UIView {
        let actions: [(String, String, AEMotionHomeAction, String)] = [
            ("New Project", "plus", .newProject, "aemotion.home.new"),
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
            ("Speed Remap", "speedometer", .speedRemap),
            ("Cutout", "person.crop.rectangle", .cutout),
            ("Depth Map", "square.3.layers.3d.down.right", .depthMap),
            ("Preset Studio", "slider.horizontal.3", .presetStudio),
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

    private func makeSectionTitle(_ value: String) -> UIView {
        let label = UILabel()
        label.text = value
        label.font = AEMotionProductTheme.sectionTitleFont()
        label.textColor = AEMotionProductTheme.primaryText
        label.adjustsFontForContentSizeCategory = true
        return label
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
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 15, leading: 10, bottom: 15, trailing: 10)
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
        configuration.baseForegroundColor = AEMotionProductTheme.accentViolet
        configuration.baseBackgroundColor = AEMotionProductTheme.accentPurple.withAlphaComponent(0.13)
        configuration.cornerStyle = .large
        self.configuration = configuration
        widthAnchor.constraint(equalToConstant: 112).isActive = true
        heightAnchor.constraint(equalToConstant: 92).isActive = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
#endif
