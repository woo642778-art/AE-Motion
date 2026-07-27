#if canImport(UIKit)
import UIKit

@MainActor
final class AEMotionSpotlightCard: UIControl {
    private let spotlightLayer = CAGradientLayer()
    private let edgeLayer = CAGradientLayer()
    private let edgeMask = CAShapeLayer()
    private let iconContainer = UIView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let badgeLabel = UILabel()
    private let arrowView = UIImageView(image: UIImage(systemName: "arrow.up.right"))
    private var pressAnimator: UIViewPropertyAnimator?

    init(
        title: String,
        subtitle: String,
        systemImage: String,
        badge: String? = nil,
        accessibilityIdentifier: String
    ) {
        super.init(frame: .zero)
        self.accessibilityIdentifier = accessibilityIdentifier
        accessibilityTraits = .button
        accessibilityLabel = title
        accessibilityHint = subtitle
        configure(title: title, subtitle: subtitle, systemImage: systemImage, badge: badge)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure(title: "", subtitle: "", systemImage: "sparkles", badge: nil)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        spotlightLayer.frame = bounds
        edgeLayer.frame = bounds
        spotlightLayer.cornerRadius = layer.cornerRadius
        edgeLayer.cornerRadius = layer.cornerRadius
        edgeMask.path = UIBezierPath(
            roundedRect: bounds,
            cornerRadius: AEMotionProductTheme.cardRadius
        ).cgPath
    }

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        let point = touch.location(in: self)
        updateSpotlight(at: point)
        spotlightLayer.opacity = 1
        animatePressed(true)
        return super.beginTracking(touch, with: event)
    }

    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        updateSpotlight(at: touch.location(in: self))
        return super.continueTracking(touch, with: event)
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        super.endTracking(touch, with: event)
        animatePressed(false)
        fadeSpotlight()
    }

    override func cancelTracking(with event: UIEvent?) {
        super.cancelTracking(with: event)
        animatePressed(false)
        fadeSpotlight()
    }

    func updateSpotlight(at point: CGPoint) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let normalized = CGPoint(
            x: min(max(point.x / bounds.width, 0), 1),
            y: min(max(point.y / bounds.height, 0), 1)
        )
        spotlightLayer.startPoint = normalized
        spotlightLayer.endPoint = CGPoint(
            x: min(max(normalized.x + 0.48, 0), 1),
            y: min(max(normalized.y + 0.48, 0), 1)
        )
    }

    private func configure(
        title: String,
        subtitle: String,
        systemImage: String,
        badge: String?
    ) {
        translatesAutoresizingMaskIntoConstraints = false
        AEMotionProductTheme.configureInteractiveSurface(self)
        layer.masksToBounds = false
        contentMode = .redraw

        spotlightLayer.type = .radial
        spotlightLayer.colors = [
            UIColor.white.withAlphaComponent(0.22).cgColor,
            AEMotionProductTheme.accentViolet.withAlphaComponent(0.16).cgColor,
            UIColor.clear.cgColor,
        ]
        spotlightLayer.locations = [0, 0.34, 1]
        spotlightLayer.opacity = 0
        layer.insertSublayer(spotlightLayer, at: 0)

        edgeLayer.type = .axial
        edgeLayer.colors = [
            AEMotionProductTheme.accentPurple.withAlphaComponent(0.54).cgColor,
            AEMotionProductTheme.accentBlue.withAlphaComponent(0.10).cgColor,
            AEMotionProductTheme.accentViolet.withAlphaComponent(0.42).cgColor,
        ]
        edgeLayer.startPoint = CGPoint(x: 0, y: 0)
        edgeLayer.endPoint = CGPoint(x: 1, y: 1)
        edgeMask.fillColor = UIColor.clear.cgColor
        edgeMask.strokeColor = UIColor.white.cgColor
        edgeMask.lineWidth = 1.25
        edgeLayer.mask = edgeMask
        layer.insertSublayer(edgeLayer, at: 1)

        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.backgroundColor = AEMotionProductTheme.accentPurple.withAlphaComponent(0.18)
        iconContainer.layer.cornerRadius = 15
        iconContainer.layer.cornerCurve = .continuous

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = UIImage(systemName: systemImage)?.applyingSymbolConfiguration(
            AEMotionProductTheme.makeIconConfiguration(pointSize: 21, weight: .bold)
        )
        iconView.tintColor = AEMotionProductTheme.accentViolet
        iconView.contentMode = .scaleAspectFit
        iconView.isAccessibilityElement = false
        iconContainer.addSubview(iconView)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = title
        titleLabel.font = AEMotionProductTheme.cardTitleFont()
        titleLabel.textColor = AEMotionProductTheme.primaryText
        titleLabel.numberOfLines = 0
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.setContentCompressionResistancePriority(.required, for: .vertical)

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.text = subtitle
        subtitleLabel.font = AEMotionProductTheme.bodyFont()
        subtitleLabel.textColor = AEMotionProductTheme.secondaryText
        subtitleLabel.numberOfLines = 0
        subtitleLabel.adjustsFontForContentSizeCategory = true

        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        badgeLabel.text = badge
        badgeLabel.font = UIFont.systemFont(ofSize: 11, weight: .bold)
        badgeLabel.textColor = .white
        badgeLabel.backgroundColor = AEMotionProductTheme.accentPurple.withAlphaComponent(0.72)
        badgeLabel.layer.cornerRadius = 8
        badgeLabel.layer.cornerCurve = .continuous
        badgeLabel.clipsToBounds = true
        badgeLabel.textAlignment = .center
        badgeLabel.isHidden = badge == nil

        arrowView.translatesAutoresizingMaskIntoConstraints = false
        arrowView.tintColor = AEMotionProductTheme.secondaryText
        arrowView.contentMode = .scaleAspectFit
        arrowView.isAccessibilityElement = false

        let labels = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        labels.axis = .vertical
        labels.spacing = 5
        labels.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconContainer)
        addSubview(labels)
        addSubview(badgeLabel)
        addSubview(arrowView)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 128),
            iconContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            iconContainer.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            iconContainer.widthAnchor.constraint(equalToConstant: 48),
            iconContainer.heightAnchor.constraint(equalToConstant: 48),
            iconView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 27),
            iconView.heightAnchor.constraint(equalToConstant: 27),

            labels.leadingAnchor.constraint(equalTo: iconContainer.trailingAnchor, constant: 15),
            labels.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            labels.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -20),
            labels.trailingAnchor.constraint(equalTo: arrowView.leadingAnchor, constant: -12),

            arrowView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            arrowView.centerYAnchor.constraint(equalTo: centerYAnchor),
            arrowView.widthAnchor.constraint(equalToConstant: 20),
            arrowView.heightAnchor.constraint(equalToConstant: 20),

            badgeLabel.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            badgeLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            badgeLabel.heightAnchor.constraint(equalToConstant: 20),
            badgeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])
    }

    private func animatePressed(_ pressed: Bool) {
        pressAnimator?.stopAnimation(true)
        let targetTransform = pressed
            ? CGAffineTransform(scaleX: 0.978, y: 0.978).translatedBy(x: 0, y: 1.5)
            : .identity
        pressAnimator = AEMotionMotionSystem.spring(
            duration: pressed ? 0.24 : 0.46,
            dampingRatio: pressed ? 0.92 : 0.76,
            animations: { [weak self] in self?.transform = targetTransform }
        )
        if pressed { AEMotionMotionSystem.impactHaptic(style: .soft) }
    }

    private func fadeSpotlight() {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = spotlightLayer.presentation()?.opacity ?? spotlightLayer.opacity
        animation.toValue = 0
        animation.duration = 0.28
        spotlightLayer.opacity = 0
        spotlightLayer.add(animation, forKey: "aemotion.spotlight.fade")
    }
}
#endif
