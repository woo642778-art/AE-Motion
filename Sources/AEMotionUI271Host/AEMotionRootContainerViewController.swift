#if canImport(UIKit)
import UIKit
import AEMotionExtensionsCore

@MainActor
final class AEMotionRootContainerViewController: UIViewController {
    let hostController: UIViewController
    let shellController: AEMotionShellViewController

    init(
        hostController: UIViewController,
        shellController: AEMotionShellViewController = .shared
    ) {
        self.hostController = hostController
        self.shellController = shellController
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AEMotionProductTheme.canvas
        embedHostController()
        embedShellController()
    }

    override var childForStatusBarStyle: UIViewController? { hostController }
    override var childForStatusBarHidden: UIViewController? { hostController }
    override var childForHomeIndicatorAutoHidden: UIViewController? { hostController }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        hostController.supportedInterfaceOrientations
    }
    override var shouldAutorotate: Bool { hostController.shouldAutorotate }

    func showShell(tab: HomeShellTab, showsHomeContent: Bool) {
        loadViewIfNeeded()
        shellController.view.isHidden = false
        shellController.configure(tab: tab, showsHomeContent: showsHomeContent)
        view.bringSubviewToFront(shellController.view)
    }

    func hideShell() {
        guard shellController.isViewLoaded else { return }
        shellController.prepareForHiddenState()
        shellController.view.isHidden = true
    }

    private func embedHostController() {
        guard hostController.parent !== self else { return }
        addChild(hostController)
        hostController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostController.view)
        NSLayoutConstraint.activate([
            hostController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        hostController.didMove(toParent: self)
    }

    private func embedShellController() {
        guard shellController.parent !== self else { return }
        addChild(shellController)
        shellController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(shellController.view)
        NSLayoutConstraint.activate([
            shellController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            shellController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            shellController.view.topAnchor.constraint(equalTo: view.topAnchor),
            shellController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        shellController.didMove(toParent: self)
        view.bringSubviewToFront(shellController.view)
    }
}
#endif
