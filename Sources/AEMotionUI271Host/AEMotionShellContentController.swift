#if canImport(UIKit)
import UIKit
import AEMotionExtensionsCore

@MainActor
final class AEMotionShellContentController: UIViewController {
    var onHomeAction: ((AEMotionHomeAction) -> Void)?

    private let homeController = AEMotionHomeViewController()
    private let tutorialController = AEMotionTutorialViewController()
    private var visibleTab: AEMotionRootTab?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AEMotionProductTheme.canvas
        view.accessibilityIdentifier = "aemotion.shell.content"

        homeController.actionHandler = { [weak self] action in
            self?.onHomeAction?(action)
        }
        embed(homeController)
        embed(tutorialController)
        show(tab: .home)
    }

    func show(tab: AEMotionRootTab) {
        loadViewIfNeeded()
        visibleTab = tab
        let showsHome = tab == .home
        let showsTutorials = tab == .tutorials

        homeController.view.isHidden = !showsHome
        homeController.view.isUserInteractionEnabled = showsHome
        tutorialController.view.isHidden = !showsTutorials
        tutorialController.view.isUserInteractionEnabled = showsTutorials
        view.isHidden = !(showsHome || showsTutorials)
        view.isUserInteractionEnabled = showsHome || showsTutorials
    }

    func prepareForHiddenState() {
        visibleTab = nil
        view.isHidden = true
        view.isUserInteractionEnabled = false
        homeController.view.isHidden = true
        homeController.view.isUserInteractionEnabled = false
        tutorialController.view.isHidden = true
        tutorialController.view.isUserInteractionEnabled = false
    }

    private func embed(_ controller: UIViewController) {
        addChild(controller)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controller.view)
        NSLayoutConstraint.activate([
            controller.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controller.view.topAnchor.constraint(equalTo: view.topAnchor),
            controller.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        controller.didMove(toParent: self)
    }
}
#endif
