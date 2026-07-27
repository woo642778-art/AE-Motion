#if canImport(UIKit)
import UIKit

@MainActor
enum AEMotionMotionSystem {
    static var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }

    @discardableResult
    static func spring(
        duration: TimeInterval = 0.52,
        dampingRatio: CGFloat = 0.82,
        initialVelocity: CGVector = .zero,
        animations: @escaping () -> Void,
        completion: ((UIViewAnimatingPosition) -> Void)? = nil
    ) -> UIViewPropertyAnimator {
        if reduceMotion {
            let animator = UIViewPropertyAnimator(duration: 0.18, curve: .easeOut, animations: animations)
            if let completion { animator.addCompletion(completion) }
            animator.startAnimation()
            return animator
        }

        let timing = UISpringTimingParameters(
            dampingRatio: dampingRatio,
            initialVelocity: initialVelocity
        )
        let animator = UIViewPropertyAnimator(duration: duration, timingParameters: timing)
        animator.isInterruptible = true
        animator.addAnimations(animations)
        if let completion { animator.addCompletion(completion) }
        animator.startAnimation()
        return animator
    }

    @discardableResult
    static func crossfade(
        _ view: UIView,
        duration: TimeInterval = 0.18,
        changes: @escaping () -> Void
    ) -> UIViewPropertyAnimator {
        let animator = UIViewPropertyAnimator(duration: duration, curve: .easeInOut) {
            UIView.transition(
                with: view,
                duration: duration,
                options: [.transitionCrossDissolve, .allowAnimatedContent, .beginFromCurrentState],
                animations: changes
            )
        }
        animator.startAnimation()
        return animator
    }

    static func selectionHaptic() {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }

    static func impactHaptic(style: UIImpactFeedbackGenerator.FeedbackStyle = .soft) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }
}
#endif
