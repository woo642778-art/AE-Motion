#if canImport(UIKit)
import UIKit

@MainActor
final class AEMotionAmbientFieldView: UIView {
    private let primaryGlow = CAGradientLayer()
    private let secondaryGlow = CAGradientLayer()
    private let grainOverlay = CAGradientLayer()
    private var isAnimationRequested = false
    private var observers: [NSObjectProtocol] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        backgroundColor = .clear
        configureLayers()
        observeApplicationState()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        backgroundColor = .clear
        configureLayers()
        observeApplicationState()
    }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        primaryGlow.frame = bounds.insetBy(dx: -bounds.width * 0.18, dy: -bounds.height * 0.15)
        secondaryGlow.frame = bounds.insetBy(dx: -bounds.width * 0.14, dy: -bounds.height * 0.18)
        grainOverlay.frame = bounds
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            pauseAnimation()
        } else if isAnimationRequested {
            resumeAnimation()
        }
    }

    func setVisibleAndActive(_ active: Bool) {
        isAnimationRequested = active
        if active, window != nil {
            resumeAnimation()
        } else {
            pauseAnimation()
        }
    }

    func pauseAnimation() {
        [primaryGlow, secondaryGlow].forEach { layer in
            guard layer.speed != 0 else { return }
            let pausedTime = layer.convertTime(CACurrentMediaTime(), from: nil)
            layer.speed = 0
            layer.timeOffset = pausedTime
        }
    }

    func resumeAnimation() {
        guard !UIAccessibility.isReduceMotionEnabled else {
            removeAmbientAnimations()
            return
        }
        [primaryGlow, secondaryGlow].forEach { layer in
            if layer.speed == 0 {
                let pausedTime = layer.timeOffset
                layer.speed = 1
                layer.timeOffset = 0
                layer.beginTime = 0
                layer.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) - pausedTime
            }
        }
        installAmbientAnimationsIfNeeded()
    }

    private func configureLayers() {
        clipsToBounds = false
        let opaqueFallback = UIAccessibility.isReduceTransparencyEnabled

        primaryGlow.type = .radial
        primaryGlow.colors = [
            AEMotionProductTheme.accentPurple.withAlphaComponent(opaqueFallback ? 0.32 : 0.46).cgColor,
            AEMotionProductTheme.accentViolet.withAlphaComponent(opaqueFallback ? 0.10 : 0.20).cgColor,
            UIColor.clear.cgColor,
        ]
        primaryGlow.locations = [0, 0.42, 1]
        primaryGlow.startPoint = CGPoint(x: 0.20, y: 0.14)
        primaryGlow.endPoint = CGPoint(x: 0.86, y: 0.92)

        secondaryGlow.type = .radial
        secondaryGlow.colors = [
            AEMotionProductTheme.accentBlue.withAlphaComponent(opaqueFallback ? 0.18 : 0.27).cgColor,
            UIColor.clear.cgColor,
        ]
        secondaryGlow.locations = [0, 1]
        secondaryGlow.startPoint = CGPoint(x: 0.80, y: 0.26)
        secondaryGlow.endPoint = CGPoint(x: 0.12, y: 0.95)

        grainOverlay.colors = [
            UIColor.white.withAlphaComponent(opaqueFallback ? 0 : 0.025).cgColor,
            UIColor.clear.cgColor,
            UIColor.black.withAlphaComponent(opaqueFallback ? 0 : 0.035).cgColor,
        ]
        grainOverlay.locations = [0, 0.5, 1]
        grainOverlay.startPoint = CGPoint(x: 0, y: 0)
        grainOverlay.endPoint = CGPoint(x: 1, y: 1)

        layer.addSublayer(primaryGlow)
        layer.addSublayer(secondaryGlow)
        layer.addSublayer(grainOverlay)
    }

    private func installAmbientAnimationsIfNeeded() {
        guard primaryGlow.animation(forKey: "aemotion.ambient.primary") == nil else { return }

        let primary = CABasicAnimation(keyPath: "transform.translation.x")
        primary.fromValue = -18
        primary.toValue = 24
        primary.duration = 7.5
        primary.autoreverses = true
        primary.repeatCount = .infinity
        primary.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        primaryGlow.add(primary, forKey: "aemotion.ambient.primary")

        let secondary = CABasicAnimation(keyPath: "transform.translation.y")
        secondary.fromValue = 20
        secondary.toValue = -22
        secondary.duration = 9.0
        secondary.autoreverses = true
        secondary.repeatCount = .infinity
        secondary.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        secondaryGlow.add(secondary, forKey: "aemotion.ambient.secondary")
    }

    private func removeAmbientAnimations() {
        primaryGlow.removeAllAnimations()
        secondaryGlow.removeAllAnimations()
    }

    private func observeApplicationState() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.pauseAnimation() }
        })
        observers.append(center.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard self?.isAnimationRequested == true else { return }
                self?.resumeAnimation()
            }
        })
    }
}
#endif
