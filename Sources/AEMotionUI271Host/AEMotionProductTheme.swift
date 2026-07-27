#if canImport(UIKit)
import UIKit

@MainActor
enum AEMotionProductTheme {
    static let minimumTouchTarget: CGFloat = 44
    static let horizontalMargin: CGFloat = 18
    static let sectionSpacing: CGFloat = 18
    static let cardRadius: CGFloat = 22
    static let compactCardRadius: CGFloat = 16
    static let navigationHeight: CGFloat = 72

    static var canvas: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.025, green: 0.024, blue: 0.038, alpha: 1)
                : UIColor(red: 0.055, green: 0.050, blue: 0.080, alpha: 1)
        }
    }

    static var surface: UIColor {
        UIColor { _ in UIColor(red: 0.075, green: 0.068, blue: 0.105, alpha: 0.96) }
    }

    static var elevatedSurface: UIColor {
        UIColor { _ in UIColor(red: 0.105, green: 0.092, blue: 0.145, alpha: 0.98) }
    }

    static var floatingSurface: UIColor {
        UIColor { _ in UIColor(red: 0.070, green: 0.063, blue: 0.098, alpha: 0.88) }
    }

    static var primaryText: UIColor { .white }
    static var secondaryText: UIColor { UIColor(white: 0.76, alpha: 1) }
    static var tertiaryText: UIColor { UIColor(white: 0.54, alpha: 1) }
    static var separator: UIColor { UIColor.white.withAlphaComponent(0.095) }
    static var accentPurple: UIColor { UIColor(red: 0.49, green: 0.24, blue: 1.0, alpha: 1) }
    static var accentViolet: UIColor { UIColor(red: 0.72, green: 0.35, blue: 1.0, alpha: 1) }
    static var accentBlue: UIColor { UIColor(red: 0.23, green: 0.54, blue: 1.0, alpha: 1) }
    static var success: UIColor { UIColor(red: 0.30, green: 0.86, blue: 0.58, alpha: 1) }

    static func titleFont() -> UIFont {
        UIFont.systemFont(ofSize: 32, weight: .bold)
    }

    static func sectionTitleFont() -> UIFont {
        UIFont.systemFont(ofSize: 20, weight: .bold)
    }

    static func cardTitleFont() -> UIFont {
        UIFont.systemFont(ofSize: 18, weight: .bold)
    }

    static func bodyFont() -> UIFont {
        UIFont.preferredFont(forTextStyle: .subheadline)
    }

    static func captionFont() -> UIFont {
        UIFont.preferredFont(forTextStyle: .caption1)
    }

    static func configureSurface(_ view: UIView, radius: CGFloat = cardRadius) {
        view.backgroundColor = surface
        view.layer.cornerRadius = radius
        view.layer.cornerCurve = .continuous
        view.layer.borderWidth = 1 / UIScreen.main.scale
        view.layer.borderColor = separator.cgColor
        view.clipsToBounds = true
    }

    static func configureInteractiveSurface(_ view: UIView, radius: CGFloat = cardRadius) {
        configureSurface(view, radius: radius)
        view.isAccessibilityElement = true
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.26
        view.layer.shadowRadius = 18
        view.layer.shadowOffset = CGSize(width: 0, height: 12)
        view.layer.masksToBounds = false
    }

    static func gradientColors(alpha: CGFloat = 1) -> [CGColor] {
        [
            accentPurple.withAlphaComponent(alpha).cgColor,
            accentViolet.withAlphaComponent(alpha * 0.88).cgColor,
            accentBlue.withAlphaComponent(alpha * 0.65).cgColor,
        ]
    }

    static func makeIconConfiguration(
        pointSize: CGFloat = 18,
        weight: UIImage.SymbolWeight = .semibold
    ) -> UIImage.SymbolConfiguration {
        UIImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
    }
}
#endif
